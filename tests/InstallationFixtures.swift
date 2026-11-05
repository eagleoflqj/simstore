import CryptoKit
import Foundation

enum InstallationFixtures {
  static let device = SimulatorDevice(
    id: "device-A", name: "iPhone", runtime: "27.0", state: "Booted")

  static func temporaryDirectory(in parent: URL = .temporaryDirectory) throws -> URL {
    let directory = parent.appending(component: "installation-test-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func version(data: Data = Data(), number: String = "1.0.0") -> CatalogVersion {
    CatalogVersion(
      version: number, minSimulatorOS: "15.0",
      sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
      size: Int64(data.count), revision: String(repeating: "a", count: 40),
      recipeRevision: String(repeating: "b", count: 40), time: 0)
  }

  static func app(version: CatalogVersion = version()) -> CatalogApp {
    CatalogApp(
      id: "example", name: "Example", bundleID: "org.example.App",
      repository: URL(string: "https://github.com/example/app")!, license: "MIT",
      description: ["en": "An example app."], categories: ["utilities"], versions: [version])
  }

  static func info(
    bundleID: String = "org.example.App", version: String = "1.0", executable: String = "Example",
    platform: String = "iPhoneSimulator"
  ) throws -> Data {
    try PropertyListSerialization.data(
      fromPropertyList: [
        "CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version,
        "CFBundleExecutable": executable, "MinimumOSVersion": "15.0",
        "CFBundleSupportedPlatforms": [platform],
      ], format: .binary, options: 0)
  }

  static func machO(platform: UInt32 = 7, cpu: UInt32 = 0x0100_000C, type: UInt32 = 2) -> Data {
    let words: [UInt32] = [0xFEED_FACF, cpu, 0, type, 1, 24, 0, 0, 0x32, 24, platform, 0, 0, 0]
    return words.reduce(into: Data()) { data, word in
      var value = word.littleEndian
      withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
  }

  static func bundle(in directory: URL) throws -> URL {
    let bundle = directory.appending(component: "Example.app")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try info().write(to: bundle.appending(component: "Info.plist"))
    try executable(machO(), at: bundle.appending(component: "Example"))
    return bundle
  }

  static func executable(_ data: Data, at path: URL) throws {
    try data.write(to: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
  }

  struct Entry {
    let path: String
    var data = Data()
    var type: UInt8 = 48
    var target = ""
    var mode = 0o644
  }

  static func entries() throws -> [Entry] {
    [
      Entry(path: "Example.app/", type: 53, mode: 0o755),
      Entry(path: "Example.app/Info.plist", data: try info()),
      Entry(path: "Example.app/Example", data: machO(), mode: 0o755),
    ]
  }

  static func archive(_ entries: [Entry], in directory: URL) throws -> URL {
    var result = Data()
    for entry in entries {
      var header = Data(repeating: 0, count: 512)
      func set(_ string: String, at offset: Int, length: Int) {
        let bytes = Data(string.utf8)
        precondition(bytes.count <= length)
        header.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
      }
      set(entry.path, at: 0, length: 100)
      set(String(format: "%07o", entry.mode), at: 100, length: 8)
      set("0000000", at: 108, length: 8)
      set("0000000", at: 116, length: 8)
      set(String(format: "%011o", entry.data.count), at: 124, length: 12)
      set("00000000000", at: 136, length: 12)
      set("        ", at: 148, length: 8)
      header[156] = entry.type
      set(entry.target, at: 157, length: 100)
      set("ustar", at: 257, length: 6)
      set("00", at: 263, length: 2)
      let sum = header.reduce(0) { $0 + Int($1) }
      set(String(format: "%06o\0 ", sum), at: 148, length: 8)
      result.append(header)
      result.append(entry.data)
      result.append(Data(repeating: 0, count: (512 - entry.data.count % 512) % 512))
    }
    result.append(Data(repeating: 0, count: 1024))
    let tar = directory.appending(component: "fixture.tar")
    try result.write(to: tar)
    let compressed = try Command.run("/usr/bin/bzip2", arguments: ["-c", tar.path])
    let archive = directory.appending(component: "fixture.tar.bz2")
    try compressed.write(to: archive)
    return archive
  }

  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw failure(message) }
  }

  static func failure(_ message: String) -> NSError {
    NSError(domain: "InstallationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  @MainActor
  static func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition() {
      guard ContinuousClock.now < deadline else {
        throw failure("An installation operation timed out.")
      }
      try await Task.sleep(for: .milliseconds(1))
    }
  }
}
