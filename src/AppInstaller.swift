import Foundation

enum AppInstallationPhase: Equatable, Sendable {
  case downloading(Int64)
  case verifying
  case extracting
  case installing
  case canceling
  case opening
  case uninstalling

  var canCancel: Bool {
    switch self {
    case .downloading, .verifying, .extracting: true
    case .installing, .canceling, .opening, .uninstalling: false
    }
  }

  var title: String {
    switch self {
    case .downloading: String(localized: "Downloading…")
    case .verifying: String(localized: "Verifying…")
    case .extracting: String(localized: "Preparing App…")
    case .installing: String(localized: "Installing…")
    case .canceling: String(localized: "Canceling…")
    case .opening: String(localized: "Opening…")
    case .uninstalling: String(localized: "Uninstalling…")
    }
  }

  func summary(totalBytes: Int64) -> String {
    if case .downloading(let bytes) = self {
      let fraction = Double(max(0, min(bytes, totalBytes))) / Double(max(1, totalBytes))
      return fraction.formatted(.percent.precision(.fractionLength(0)))
    }
    return title
  }
}

struct AppInstaller: Sendable {
  typealias Download = @Sendable (URL, URL, @escaping AppDownload.Progress) async throws -> Void
  typealias Progress = @MainActor @Sendable (AppInstallationPhase) -> Void

  var download: Download = { try await AppDownload.fetch(from: $0, to: $1, progress: $2) }
  var command: Command.Runner = Command.run
  var temporaryDirectory = URL.temporaryDirectory

  func install(
    app: CatalogApp, version: CatalogVersion, on device: SimulatorDevice,
    progress: @escaping Progress
  ) async throws {
    guard device.state == "Booted" else { throw SimulatorApplicationsError.notRunning }
    try Task.checkCancellation()
    let directory = temporaryDirectory.appending(
      component: "\(AppConfiguration.applicationIdentifier)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = directory.appending(component: "app.tar.bz2")
    let url = AppConfiguration.assetURL(
      appID: app.id, version: version.version, filename: "\(app.id).app.tar.bz2")
    await progress(.downloading(0))
    try await download(url, archive) { bytes in
      Task { @MainActor in progress(.downloading(bytes)) }
    }
    try Task.checkCancellation()
    await progress(.verifying)
    let preparation = Task.detached(priority: .userInitiated) {
      try AppPackage.verify(archive, version: version)
      try Task.checkCancellation()
      await progress(.extracting)
      let bundle = try AppPackage.extract(
        archive, to: directory.appending(component: "contents"), command: command)
      try AppPackage.validate(bundle, app: app, version: version)
      try Task.checkCancellation()
      return bundle
    }
    let bundle = try await withTaskCancellationHandler {
      try await preparation.value
    } onCancel: {
      preparation.cancel()
    }
    try Task.checkCancellation()
    await progress(.installing)
    try Task.checkCancellation()
    try await SimulatorApplications.install(bundle, on: device, command: command)
  }

  func open(app: CatalogApp, on device: SimulatorDevice) async throws {
    try await SimulatorApplications.launch(app.bundleID, on: device, command: command)
  }

  func uninstall(app: CatalogApp, on device: SimulatorDevice) async throws {
    try await SimulatorApplications.uninstall(app.bundleID, on: device, command: command)
  }
}
