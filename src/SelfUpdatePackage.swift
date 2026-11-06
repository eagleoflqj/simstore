import Foundation
import MachO

enum SelfUpdatePackage {
  static func validate(
    _ application: URL, release: SelfUpdateRelease, bundleID: String,
    os: String = currentOS
  ) throws {
    let root = application.standardizedFileURL
    guard application.lastPathComponent == "SimStore.app",
      try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
      release.isCompatible(with: os)
    else { throw SelfUpdateError.incompatiblePackage }
    let info = try info(at: root)
    let build = try SelfUpdateBuild.read(at: root)
    guard info["CFBundlePackageType"] as? String == "APPL",
      info["CFBundleIdentifier"] as? String == bundleID,
      build.version == release.version, build.build == release.build,
      build.revision == release.revision, build.time == release.time, !build.dirty,
      info["LSMinimumSystemVersion"] as? String == release.minOS,
      let name = info["CFBundleExecutable"] as? String, !name.isEmpty,
      name != ".", name != "..", !name.contains("/")
    else { throw SelfUpdateError.wrongApplication }
    let main = root.appending(path: "Contents/MacOS").appending(component: name)
    let helper = root.appending(path: "Contents/Helpers/SimStoreUpdater")
    let required = Set([main, helper].map { $0.resolvingSymlinksInPath() })
    guard required.allSatisfy({ FileManager.default.isExecutableFile(atPath: $0.path) }) else {
      throw SelfUpdateError.wrongApplication
    }
    var enumerationError: Error?
    guard
      let files = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey],
        errorHandler: { _, error in
          enumerationError = error
          return false
        })
    else { throw SelfUpdateError.wrongApplication }
    var checked: Set<URL> = []
    for case let path as URL in files {
      try Task.checkCancellation()
      let resolved = path.resolvingSymlinksInPath().standardizedFileURL
      guard resolved.pathComponents.starts(with: root.pathComponents),
        FileManager.default.fileExists(atPath: resolved.path)
      else { throw SelfUpdateError.wrongApplication }
      guard try path.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
        !checked.contains(resolved)
      else { continue }
      let file = try FileHandle(forReadingFrom: path)
      let magic = try file.read(upToCount: 4) ?? Data()
      try file.close()
      guard MachOValidation.isMachO(magic) else { continue }
      let minimum: CatalogVersionNumber
      do {
        minimum = try MachOValidation.validate(
          Data(contentsOf: path, options: .mappedIfSafe), platform: UInt32(PLATFORM_MACOS),
          isExecutable: required.contains(resolved))
      } catch {
        throw SelfUpdateError.incompatiblePackage
      }
      guard let declaredMinimum = CatalogVersionNumber(release.minOS), minimum <= declaredMinimum,
        resolved != main.resolvingSymlinksInPath() || minimum == declaredMinimum
      else { throw SelfUpdateError.incompatiblePackage }
      checked.insert(resolved)
    }
    if let enumerationError { throw enumerationError }
    guard required.isSubset(of: checked) else { throw SelfUpdateError.wrongApplication }
  }

  static var currentOS: String {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
  }

  static func info(at application: URL) throws -> [String: Any] {
    guard
      let info = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: application.appending(path: "Contents/Info.plist")), format: nil
      ) as? [String: Any]
    else { throw SelfUpdateError.wrongApplication }
    return info
  }
}
