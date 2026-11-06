import AppKit

@main
struct SelfUpdateIntegrationTest {
  @MainActor
  static func main() async {
    do {
      try await run()
      print(
        "PASS: assistant waits for the running app, replaces an isolated copy, restarts it, and removes the previous bundle."
      )
    } catch {
      FileHandle.standardError.write(
        Data("Self-update integration failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  @MainActor
  static func run() async throws {
    guard CommandLine.arguments.count == 2 else {
      throw SelfUpdateFixtures.failure("Expected the built app path.")
    }
    let source = URL(fileURLWithPath: CommandLine.arguments[1])
    let directory = try SelfUpdateFixtures.directory()
    let identifier = "org.example.SimStoreUpdateTest.\(UUID().uuidString)"
    defer {
      for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) {
        app.forceTerminate()
      }
      try? FileManager.default.removeItem(at: directory)
    }
    let application = directory.appending(component: "SimStore.app")
    try FileManager.default.copyItem(at: source, to: application)
    var info = try SelfUpdatePackage.info(at: application)
    info["CFBundleIdentifier"] = identifier
    try SelfUpdateFixtures.writeInfo(info, at: application)
    let chinese = SelfUpdateInstallation.localizationBundle(
      application: application, language: "zh-Hans")
    try SelfUpdateFixtures.require(
      SelfUpdateError.launchFailed.message(in: chinese) == "新版应用无法启动，已恢复旧版。",
      "The assistant must localize failure reports using the app's resources.")
    let current = try SelfUpdateBuild.read(at: application)
    let work = directory.appending(component: ".simstore-update-\(UUID())")
    try FileManager.default.createDirectory(
      at: work.appending(component: "payload"), withIntermediateDirectories: true)
    let payload = SelfUpdateRequest.payload(in: work)
    try FileManager.default.copyItem(at: application, to: payload)
    info["CFBundleVersion"] = String(current.build + 1)
    info["SimStoreSourceDirty"] = false
    info["SimStoreRevision"] = String(repeating: "c", count: 40)
    try SelfUpdateFixtures.writeInfo(info, at: payload)
    let release = try SelfUpdateFixtures.release([
      "tag": "latest", "version": current.version, "build": current.build + 1,
      "revision": String(repeating: "c", count: 40), "time": current.time,
      "minOS": info["LSMinimumSystemVersion"] as! String,
    ])
    let helper = work.appending(component: "SimStoreUpdater")
    try FileManager.default.copyItem(
      at: application.appending(path: "Contents/Helpers/SimStoreUpdater"), to: helper)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.allowsRunningApplicationSubstitution = false
    let running = try await NSWorkspace.shared.openApplication(
      at: application, configuration: configuration)
    let report = directory.appending(component: "error.json")
    let request = SelfUpdateRequest(
      application: application, bundleID: identifier, currentRevision: current.revision,
      parentPID: running.processIdentifier, release: release, reportURL: report)
    try JSONEncoder().encode(request).write(
      to: work.appending(component: SelfUpdateRequest.filename))
    let process = Process()
    process.executableURL = helper
    process.arguments = [work.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.standardError
    try process.run()
    defer { if process.isRunning { process.terminate() } }
    try await wait {
      FileManager.default.fileExists(atPath: work.appending(component: "ready").path)
        || !process.isRunning
    }
    try SelfUpdateFixtures.require(
      process.isRunning, "The assistant must validate the request and become ready.")
    try await Task.sleep(for: .milliseconds(200))
    try SelfUpdateFixtures.require(
      !running.isTerminated, "The assistant must not kill the current app.")
    try SelfUpdateFixtures.require(
      try SelfUpdateBuild.read(at: application) == current,
      "Do not replace files before the parent exits.")
    try SelfUpdateFixtures.require(running.terminate(), "The isolated old copy must quit normally.")
    try await wait { !process.isRunning }
    if FileManager.default.fileExists(atPath: report.path) {
      throw SelfUpdateFixtures.failure(
        try JSONDecoder().decode(String.self, from: Data(contentsOf: report)))
    }
    try SelfUpdateFixtures.require(
      process.terminationStatus == 0, "The assistant must finish successfully.")
    try SelfUpdateFixtures.require(
      try SelfUpdateBuild.read(at: application).build == current.build + 1,
      "Install the prepared build.")
    let reopened = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first
    {
      $0.processIdentifier != running.processIdentifier && !$0.isTerminated
    }
    try SelfUpdateFixtures.require(
      reopened != nil, "Restart the new bundle at its original location.")
    try SelfUpdateFixtures.require(
      !FileManager.default.fileExists(atPath: work.path),
      "Remove the assistant and previous bundle after launch succeeds.")
    reopened?.terminate()
    try await wait { reopened?.isTerminated != false }
  }

  @MainActor
  static func wait(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while !predicate() {
      guard ContinuousClock.now < deadline else {
        throw SelfUpdateFixtures.failure("The helper integration timed out.")
      }
      try await Task.sleep(for: .milliseconds(50))
    }
  }
}
