import AppKit
import Darwin

struct SelfUpdateRequest: Codable, Sendable {
  let application: URL
  let bundleID: String
  let currentRevision: String
  let parentPID: Int32
  let release: SelfUpdateRelease
  let reportURL: URL
  var language = "en"

  static let filename = "request.json"

  static func read(from directory: URL) throws -> SelfUpdateRequest {
    let request = try JSONDecoder().decode(
      Self.self, from: Data(contentsOf: directory.appending(component: filename)))
    guard request.application.isFileURL, request.application.pathExtension == "app",
      request.reportURL.isFileURL, request.parentPID > 1, request.parentPID != getpid(),
      directory.lastPathComponent.hasPrefix(".simstore-update-"),
      directory.deletingLastPathComponent().resolvingSymlinksInPath()
        == request.application.deletingLastPathComponent().resolvingSymlinksInPath(),
      directory.resolvingSymlinksInPath() == directory.standardizedFileURL,
      try SelfUpdatePackage.info(at: request.application)["CFBundleIdentifier"] as? String
        == request.bundleID,
      try SelfUpdateBuild.read(at: request.application).revision == request.currentRevision
    else { throw SelfUpdateError.wrongApplication }
    return request
  }

  static func payload(in directory: URL) -> URL {
    directory.appending(path: "payload/SimStore.app")
  }
}

enum SelfUpdateInstallation {
  typealias Launch = @MainActor (URL) async throws -> Void

  static func isRunning(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
  }

  static func waitForExit(_ pid: Int32, timeout: Duration = .seconds(30)) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while isRunning(pid) {
      guard ContinuousClock.now < deadline else { throw SelfUpdateError.quitTimedOut }
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  @MainActor
  static func replace(
    request: SelfUpdateRequest, directory: URL, launch: Launch = launchApplication
  ) async throws {
    let payload = SelfUpdateRequest.payload(in: directory)
    try SelfUpdatePackage.validate(payload, release: request.release, bundleID: request.bundleID)
    try exchange(request.application, payload)
    do {
      try await launch(request.application)
    } catch {
      do {
        try exchange(request.application, payload)
      } catch {
        throw SelfUpdateError.recoveryFailed(payload)
      }
      throw SelfUpdateError.launchFailed
    }
  }

  private static func exchange(_ application: URL, _ payload: URL) throws {
    // Both directories are on the same volume. Keep the old app at the payload path until launch succeeds.
    guard renameatx_np(AT_FDCWD, application.path, AT_FDCWD, payload.path, UInt32(RENAME_SWAP)) == 0
    else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
  }

  @MainActor
  static func launchApplication(_ application: URL) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.allowsRunningApplicationSubstitution = false
    let running = try await NSWorkspace.shared.openApplication(
      at: application, configuration: configuration)
    try await Task.sleep(for: .seconds(3))
    guard !running.isTerminated else { throw SelfUpdateError.launchFailed }
  }

  static func localizationBundle(application: URL, language: String) -> Bundle {
    guard let bundle = Bundle(url: application),
      let resource = bundle.url(forResource: language, withExtension: "lproj"),
      let translation = Bundle(url: resource)
    else { return Bundle(url: application) ?? .main }
    return translation
  }

  static func message(_ error: Error, bundle: Bundle) -> String {
    (error as? SelfUpdateError)?.message(in: bundle) ?? error.localizedDescription
  }

  static func writeFailure(_ error: Error, to reportURL: URL, bundle: Bundle = .main) throws {
    try FileManager.default.createDirectory(
      at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(message(error, bundle: bundle)).write(to: reportURL, options: .atomic)
  }

  static func consumeFailure(at reportURL: URL) -> String? {
    guard let data = try? Data(contentsOf: reportURL),
      let message = try? JSONDecoder().decode(String.self, from: data)
    else { return nil }
    try? FileManager.default.removeItem(at: reportURL)
    return message
  }

  @MainActor
  static func showFailure(_ error: Error, bundle: Bundle) {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = String(localized: "Couldn’t Update SimStore", bundle: bundle)
    alert.informativeText = message(error, bundle: bundle)
    alert.addButton(withTitle: String(localized: "OK", bundle: bundle))
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.activate(ignoringOtherApps: true)
    alert.runModal()
  }
}
