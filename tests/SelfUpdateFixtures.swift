import CryptoKit
import Foundation

enum SelfUpdateFixtures {
  static let bundleID = "org.example.SimStoreTest"

  static func directory() throws -> URL {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appending(path: "self-update-tests/\(UUID())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func release(_ changes: [String: Any] = [:]) throws -> SelfUpdateRelease {
    var value: [String: Any] = [
      "tag": "0.2.0", "version": "0.2.0", "build": 0, "minOS": "14.0",
      "revision": String(repeating: "b", count: 40), "time": 1_700_000_000,
      "size": 1, "sha256": String(repeating: "a", count: 64),
    ]
    value.merge(changes) { _, new in new }
    return try JSONDecoder().decode(
      SelfUpdateRelease.self, from: JSONSerialization.data(withJSONObject: value))
  }

  static func current(version: String = "0.1.0", build: Int = 0) -> SelfUpdateBuild {
    SelfUpdateBuild(
      version: version, build: build, revision: String(repeating: "a", count: 40), time: 1,
      dirty: false)
  }

  static func index(_ versions: [SelfUpdateRelease]) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "versions": try versions.map {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
      }
    ])
  }

  static func bundle(in directory: URL, release: SelfUpdateRelease) throws -> URL {
    let application = directory.appending(component: "SimStore.app")
    for path in ["Contents/MacOS", "Contents/Helpers"] {
      try FileManager.default.createDirectory(
        at: application.appending(path: path), withIntermediateDirectories: true)
    }
    let info: [String: Any] = [
      "CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL",
      "CFBundleExecutable": "SimStore",
      "CFBundleShortVersionString": release.version, "CFBundleVersion": String(release.build),
      "SimStoreRevision": release.revision, "SimStoreCommitTime": release.time,
      "SimStoreSourceDirty": false,
      "LSMinimumSystemVersion": release.minOS,
    ]
    try writeInfo(info, at: application)
    for path in ["Contents/MacOS/SimStore", "Contents/Helpers/SimStoreUpdater"] {
      let file = application.appending(path: path)
      try machO().write(to: file)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }
    return application
  }

  static func writeInfo(_ info: [String: Any], at application: URL) throws {
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: application.appending(path: "Contents/Info.plist"))
  }

  static func machO(platform: UInt32 = 1, cpu: UInt32 = 0x0100_000C, minOS: UInt32 = 14 << 16)
    -> Data
  {
    [UInt32(0xFEED_FACF), cpu, 0, 2, 1, 24, 0, 0, 0x32, 24, platform, minOS, 0, 0].reduce(
      into: Data()
    ) { data, word in
      var value = word.littleEndian
      withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
  }

  static func archive(_ application: URL, in directory: URL) throws -> URL {
    let archive = directory.appending(component: "SimStore.app.tar.bz2")
    _ = try Command.run(
      "/usr/bin/tar",
      arguments: [
        "-cjf", archive.path, "-C", application.deletingLastPathComponent().path,
        application.lastPathComponent,
      ])
    return archive
  }

  static func archivedRelease(_ archive: URL, release: SelfUpdateRelease) throws
    -> SelfUpdateRelease
  {
    let data = try Data(contentsOf: archive)
    var value =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(release)) as! [String: Any]
    value["size"] = data.count
    value["sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return try JSONDecoder().decode(
      SelfUpdateRelease.self, from: JSONSerialization.data(withJSONObject: value))
  }

  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw failure(message) }
  }

  static func failure(_ message: String) -> NSError {
    NSError(domain: "SelfUpdateTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  static func rejects(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw failure("Invalid update input must fail.")
  }

  @MainActor
  static func eventually(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !predicate() {
      guard ContinuousClock.now < deadline else {
        throw failure("Timed out waiting for the updater.")
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
}
