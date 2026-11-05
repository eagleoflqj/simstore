import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import OSLog

actor IconCache {
  struct Key: Hashable, Sendable {
    let url: URL
    let recipeRevision: String

    var filename: String {
      SHA256.hash(data: Data("\(url.absoluteString)\n\(recipeRevision)".utf8))
        .map { String(format: "%02x", $0) }.joined() + ".png"
    }
  }

  typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
  static let shared = IconCache()
  private static let logger = Logger(
    subsystem: AppConfiguration.applicationIdentifier, category: "Icons")

  private let directory: URL
  private let diskLimit: Int
  private let maximumConcurrentDownloads: Int
  private let transport: Transport
  private let memory = NSCache<NSString, CGImage>()
  private var requests: [Key: Task<CGImage, Error>] = [:]
  private var activeDownloads = 0
  private var downloadWaiters: [CheckedContinuation<Void, Never>] = []
  private var hasTrimmedDisk = false

  init(
    directory: URL = AppConfiguration.cacheDirectory.appending(component: "icons"),
    memoryLimit: Int = 32 * 1024 * 1024,
    diskLimit: Int = 64 * 1024 * 1024,
    maximumConcurrentDownloads: Int = 4,
    transport: Transport? = nil
  ) {
    precondition(memoryLimit > 0 && diskLimit >= 0 && maximumConcurrentDownloads > 0)
    self.directory = directory
    self.diskLimit = diskLimit
    self.maximumConcurrentDownloads = maximumConcurrentDownloads
    memory.totalCostLimit = memoryLimit
    if let transport {
      self.transport = transport
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.urlCache = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      let session = URLSession(configuration: configuration)
      self.transport = { try await session.data(for: $0) }
    }
  }

  func image(for key: Key) async throws -> CGImage {
    try Task.checkCancellation()
    let path = directory.appending(component: key.filename)
    if let image = memory.object(forKey: key.filename as NSString) {
      touch(path)
      return image
    }
    if let request = requests[key] {
      let image = try await request.value
      try Task.checkCancellation()
      return image
    }

    // The cache owns this task so one disappearing view cannot cancel other callers.
    let request = Task {
      do {
        return try await load(key, from: path)
      } catch {
        Self.logger.error(
          "Could not load icon \(key.url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        throw error
      }
    }
    requests[key] = request
    defer { requests[key] = nil }
    let image = try await request.value
    try Task.checkCancellation()
    return image
  }

  private func load(_ key: Key, from path: URL) async throws -> CGImage {
    if let data = try? Data(contentsOf: path) {
      if let image = Self.decode(data) {
        touch(path)
        trimDiskOnce()
        remember(image, for: key)
        return image
      }
      try? FileManager.default.removeItem(at: path)
    }
    trimDiskOnce()

    await acquireDownload()
    defer { releaseDownload() }
    var request = URLRequest(url: key.url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.timeoutInterval = 30
    let (data, response) = try await transport(request)
    guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
    guard (200..<300).contains(response.statusCode) else {
      throw Failure.httpStatus(response.statusCode)
    }
    guard let image = Self.decode(data) else { throw Failure.invalidImage }
    remember(image, for: key)
    if data.count <= diskLimit {
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: path, options: .atomic)
        trimDisk()
      } catch {
        Self.logger.error(
          "Could not save icon cache: \(error.localizedDescription, privacy: .public)")
      }
    }
    return image
  }

  private func remember(_ image: CGImage, for key: Key) {
    memory.setObject(
      image, forKey: key.filename as NSString, cost: image.bytesPerRow * image.height)
  }

  private func acquireDownload() async {
    if activeDownloads < maximumConcurrentDownloads {
      activeDownloads += 1
    } else {
      await withCheckedContinuation { downloadWaiters.append($0) }
    }
  }

  private func releaseDownload() {
    if downloadWaiters.isEmpty {
      activeDownloads -= 1
    } else {
      downloadWaiters.removeFirst().resume()
    }
  }

  private func touch(_ path: URL) {
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
  }

  private func trimDiskOnce() {
    if !hasTrimmedDisk {
      hasTrimmedDisk = true
      trimDisk()
    }
  }

  private func trimDisk() {
    let properties: Set<URLResourceKey> = [
      .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
    ]
    guard
      let paths = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: Array(properties), options: .skipsHiddenFiles)
    else { return }
    let entries = paths.compactMap { path -> (url: URL, size: Int, date: Date)? in
      let name = path.deletingPathExtension().lastPathComponent
      guard path.pathExtension == "png", name.count == 64,
        name.allSatisfy({ "0123456789abcdef".contains($0) }),
        let values = try? path.resourceValues(forKeys: properties), values.isRegularFile == true
      else { return nil }
      return (path, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
    }.sorted {
      $0.date == $1.date ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.date < $1.date
    }
    var size = entries.reduce(0) { $0 + $1.size }
    for entry in entries where size > diskLimit {
      do {
        try FileManager.default.removeItem(at: entry.url)
        size -= entry.size
      } catch {
        Self.logger.error(
          "Could not remove cached icon: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private static func decode(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: 256,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceShouldAllowFloat: false,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  enum Failure: Error {
    case invalidResponse
    case httpStatus(Int)
    case invalidImage
  }
}
