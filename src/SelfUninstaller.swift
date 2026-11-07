import AppKit

enum SelfUninstaller {
  @MainActor
  static func start() async throws {
    let application = Bundle.main.bundleURL.resolvingSymlinksInPath()
    let bundleID = AppConfiguration.applicationIdentifier
    _ = try SelfUninstallPlan(application: application, bundleID: bundleID)
    let directory = URL.temporaryDirectory.appending(
      component: "\(bundleID).uninstall-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = SelfUninstallRequest(
      application: application, bundleID: bundleID, parentPID: getpid(),
      language: Bundle.main.preferredLocalizations.first ?? "en")
    try JSONEncoder().encode(request).write(
      to: directory.appending(component: "request.json"), options: .atomic)
    let helper = directory.appending(component: "SimStoreUpdater")
    try FileManager.default.copyItem(
      at: application.appending(path: "Contents/Helpers/SimStoreUpdater"), to: helper)
    let process = Process()
    process.executableURL = helper
    process.arguments = ["--uninstall", directory.path]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    while process.isRunning { try await Task.sleep(for: .milliseconds(100)) }
    // Successful cleanup kills this process. A return means the assistant failed.
    if let data = try? Data(contentsOf: directory.appending(component: "error.json")),
      let message = try? JSONDecoder().decode(String.self, from: data)
    {
      throw NSError(
        domain: "SelfUninstall", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    throw SelfUninstallError.helperFailed
  }
}
