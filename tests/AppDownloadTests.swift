import Darwin
import Foundation

enum AppDownloadTests {
  @MainActor
  static func run() async throws {
    let directory = try InstallationFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let payload = Data(repeating: 0x42, count: 4 * 1024 * 1024)
    let server = try DownloadTestServer(data: payload)
    let serving = Task.detached { server.serve() }
    let counter = DownloadCounter()
    let destination = directory.appending(component: "download")
    try await AppDownload.fetch(from: server.url, to: destination) { counter.record($0) }
    await serving.value
    try InstallationFixtures.require(counter.bytes > 0, "Real HTTP downloads must report progress.")
    try InstallationFixtures.require(
      try Data(contentsOf: destination) == payload, "Write the complete download to disk.")

    let failureServer = try DownloadTestServer(data: Data("Unavailable".utf8), status: 503)
    let failedServing = Task.detached { failureServer.serve() }
    let failed = directory.appending(component: "failed")
    do {
      try await AppDownload.fetch(from: failureServer.url, to: failed) { _ in }
      throw InstallationFixtures.failure("Do not accept HTTP errors as downloads.")
    } catch AppDownload.Failure.httpStatus(503) {}
    await failedServing.value
    try InstallationFixtures.require(
      !FileManager.default.fileExists(atPath: failed.path), "Discard failed HTTP responses.")

    let cancelServer = try DownloadTestServer(data: payload)
    let cancelServing = Task.detached { cancelServer.serve() }
    let canceled = directory.appending(component: "canceled")
    let cancelCounter = DownloadCounter()
    let download = Task {
      try await AppDownload.fetch(from: cancelServer.url, to: canceled) { cancelCounter.record($0) }
    }
    try await InstallationFixtures.eventually { cancelCounter.bytes > 0 }
    download.cancel()
    do {
      try await download.value
      throw InstallationFixtures.failure("A canceled download must throw.")
    } catch is CancellationError {}
    await cancelServing.value
    try InstallationFixtures.require(
      !FileManager.default.fileExists(atPath: canceled.path), "Remove canceled downloads.")
    do {
      try await AppDownload.fetch(from: server.url, to: destination) { _ in }
      throw InstallationFixtures.failure("Do not replace an existing destination.")
    } catch CocoaError.fileWriteFileExists {}
    try InstallationFixtures.require(
      try Data(contentsOf: destination) == payload,
      "Preserve a pre-existing file when a download cannot start.")
  }
}

private final class DownloadCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var received: Int64 = 0
  var bytes: Int64 { lock.withLock { received } }
  func record(_ bytes: Int64) { lock.withLock { received = max(received, bytes) } }
}

private final class DownloadTestServer: Sendable {
  let url: URL
  private let socket: Int32
  private let data: Data
  private let status: Int

  init(data: Data, status: Int = 200) throws {
    let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard socket >= 0 else { throw InstallationFixtures.failure("Cannot open test socket.") }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0, listen(socket, 1) == 0 else {
      close(socket)
      throw InstallationFixtures.failure("Cannot bind test socket.")
    }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
    }
    guard named == 0 else {
      close(socket)
      throw InstallationFixtures.failure("Cannot read test port.")
    }
    self.socket = socket
    self.data = data
    self.status = status
    url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))/app.tar.bz2")!
  }

  func serve() {
    defer { close(socket) }
    var descriptor = pollfd(fd: socket, events: Int16(POLLIN), revents: 0)
    guard poll(&descriptor, 1, 5000) > 0 else { return }
    let client = accept(socket, nil, nil)
    guard client >= 0 else { return }
    defer { close(client) }
    var noSignal: Int32 = 1
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var request = [UInt8](repeating: 0, count: 8192)
    guard recv(client, &request, request.count, 0) > 0 else { return }
    let header = Data(
      "HTTP/1.1 \(status) Test\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
    guard write(header, to: client) else { return }
    for offset in stride(from: 0, to: data.count, by: 32 * 1024) {
      guard write(data.subdata(in: offset..<min(data.count, offset + 32 * 1024)), to: client) else {
        return
      }
      Thread.sleep(forTimeInterval: 0.005)
    }
  }

  private func write(_ bytes: Data, to client: Int32) -> Bool {
    bytes.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        let count = send(client, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
        if count <= 0 { return false }
        offset += count
      }
      return true
    }
  }
}
