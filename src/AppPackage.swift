import CryptoKit
import Foundation
import MachO

enum AppPackage {
  static func verify(_ archive: URL, version: CatalogVersion) throws {
    let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard size.map(Int64.init) == version.size else { throw Failure.sizeMismatch }
    let file = try FileHandle(forReadingFrom: archive)
    defer { try? file.close() }
    var hash = SHA256()
    while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
      try Task.checkCancellation()
      hash.update(data: chunk)
    }
    let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
    guard digest == version.sha256 else { throw Failure.checksumMismatch }
  }

  static func extract(
    _ archive: URL, to directory: URL, command: Command.Runner = Command.run
  ) throws -> URL {
    let listing = try command("/usr/bin/tar", ["-tjf", archive.path])
    let paths = String(decoding: listing, as: UTF8.self).split(separator: "\n")
    guard !paths.isEmpty,
      paths.allSatisfy({ path in
        !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
      })
    else { throw Failure.invalidArchive }
    try Task.checkCancellation()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    // Keep bsdtar's default protections against dot-dot paths and symlink traversal.
    _ = try command(
      "/usr/bin/tar",
      [
        "-xjf", archive.path, "-C", directory.path, "--no-same-owner", "--no-same-permissions",
      ])
    try Task.checkCancellation()
    let roots = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard roots.count == 1, let app = roots.first, app.pathExtension == "app",
      try app.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
      try app.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
    else { throw Failure.invalidArchive }
    return app
  }

  static func validate(_ bundle: URL, app: CatalogApp, version: CatalogVersion) throws {
    let root = bundle.resolvingSymlinksInPath().standardizedFileURL
    let info = try bundleInfo(root)
    guard info["CFBundleIdentifier"] as? String == app.bundleID,
      let actualVersion = info["CFBundleShortVersionString"] as? String,
      CatalogVersionNumber(actualVersion) == CatalogVersionNumber(version.version)
    else { throw Failure.wrongApp }
    var required: Set<URL> = []
    var checked: Set<URL> = []
    var enumerationError: Error?
    guard
      let files = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        errorHandler: { _, error in
          enumerationError = error
          return false
        })
    else { throw Failure.invalidBundle }
    let mainExecutable = try executable(in: root, info: info)
    required.insert(mainExecutable)
    try validatePlatform(info)
    for case let path as URL in files {
      try Task.checkCancellation()
      let resolved = path.resolvingSymlinksInPath().standardizedFileURL
      guard resolved.pathComponents.starts(with: root.pathComponents),
        FileManager.default.fileExists(atPath: resolved.path)
      else { throw Failure.invalidBundle }
      if ["app", "appex", "framework"].contains(path.pathExtension) {
        let nestedInfo = try bundleInfo(path)
        required.insert(try executable(in: path, info: nestedInfo))
        if path.pathExtension != "framework" { try validatePlatform(nestedInfo) }
      }
      guard try path.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
        !checked.contains(resolved)
      else { continue }
      let file = try FileHandle(forReadingFrom: path)
      let magic = try file.read(upToCount: 4)
      try file.close()
      guard let magic, magic.count == 4,
        [
          MH_MAGIC_64, MH_CIGAM_64, MH_MAGIC, MH_CIGAM,
          FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64,
        ].contains(word(magic, at: 0))
      else { continue }
      let data = try Data(contentsOf: path, options: .mappedIfSafe)
      try validateMachO(data, isMainExecutable: resolved == mainExecutable)
      checked.insert(resolved)
    }
    if let enumerationError { throw enumerationError }
    guard required.isSubset(of: checked) else { throw Failure.invalidBundle }
  }

  private static func bundleInfo(_ bundle: URL) throws -> [String: Any] {
    let candidates = [
      bundle.appending(path: "Info.plist"), bundle.appending(path: "Resources/Info.plist"),
    ]
    guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
      let info = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: path), format: nil) as? [String: Any]
    else { throw Failure.invalidBundle }
    return info
  }

  private static func executable(in bundle: URL, info: [String: Any]) throws -> URL {
    guard let name = info["CFBundleExecutable"] as? String, !name.isEmpty,
      name != ".", name != "..", !name.contains("/"),
      FileManager.default.isExecutableFile(atPath: bundle.appending(component: name).path)
    else { throw Failure.invalidBundle }
    return bundle.appending(component: name).resolvingSymlinksInPath().standardizedFileURL
  }

  private static func validatePlatform(_ info: [String: Any]) throws {
    guard info["CFBundleSupportedPlatforms"] as? [String] == ["iPhoneSimulator"],
      let minimum = info["MinimumOSVersion"] as? String, CatalogVersionNumber(minimum) != nil
    else { throw Failure.invalidBundle }
  }

  private static func validateMachO(_ data: Data, isMainExecutable: Bool) throws {
    guard data.count >= 32, word(data, at: 0) == MH_MAGIC_64,
      word(data, at: 4) == UInt32(CPU_TYPE_ARM64),
      !isMainExecutable || word(data, at: 12) == MH_EXECUTE
    else { throw Failure.unsupportedBinary }
    let count = Int(word(data, at: 16))
    let end = 32 + Int(word(data, at: 20))
    guard end <= data.count, count <= (end - 32) / 8 else { throw Failure.unsupportedBinary }
    var offset = 32
    var platforms: [UInt32] = []
    for _ in 0..<count {
      guard offset + 8 <= end else { throw Failure.unsupportedBinary }
      let command = word(data, at: offset)
      let size = Int(word(data, at: offset + 4))
      guard size >= 8, offset + size <= end else { throw Failure.unsupportedBinary }
      if command == LC_BUILD_VERSION {
        guard size >= 24 else { throw Failure.unsupportedBinary }
        platforms.append(word(data, at: offset + 8))
      }
      offset += size
    }
    guard offset == end, platforms == [UInt32(PLATFORM_IOSSIMULATOR)] else {
      throw Failure.unsupportedBinary
    }
  }

  private static func word(_ data: Data, at offset: Int) -> UInt32 {
    data.withUnsafeBytes {
      UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
  }

  enum Failure: LocalizedError {
    case sizeMismatch, checksumMismatch, invalidArchive, wrongApp, invalidBundle, unsupportedBinary

    var errorDescription: String? {
      switch self {
      case .sizeMismatch:
        String(localized: "The downloaded file has the wrong size. Try downloading it again.")
      case .checksumMismatch:
        String(localized: "The downloaded file failed its SHA-256 check. Try downloading it again.")
      case .invalidArchive:
        String(localized: "The download must contain exactly one app bundle with safe file paths.")
      case .wrongApp:
        String(localized: "The downloaded app does not match the selected app and version.")
      case .invalidBundle:
        String(localized: "The downloaded app bundle is invalid.")
      case .unsupportedBinary:
        String(localized: "The app must contain only arm64 iOS Simulator binaries.")
      }
    }
  }
}
