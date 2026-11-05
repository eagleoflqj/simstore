import Foundation

@main
@MainActor
struct AppInstallationTests {
  static func main() async {
    do {
      try AppPackageTests.run()
      try await AppDownloadTests.run()
      try await pipeline()
      try await failureAndCleanup()
      try await perDeviceJobs()
      try await cancellationDuringPreparation()
      try await installingCannotBeCanceled()
      try await stoppedDevice()
      print(
        "PASS: package verification, safe extraction, Simulator binaries, install/open, per-device jobs, cancellation, failures, and cleanup."
      )
    } catch {
      FileHandle.standardError.write(
        Data("Installation test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  static func pipeline() async throws {
    let directory = try InstallationFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = try archiveData(in: directory)
    let work = directory.appending(component: "work")
    let commands = InstallationCommands()
    let installer = AppInstaller(
      download: { url, destination, progress in
        try InstallationFixtures.require(
          url
            == AppConfiguration.assetURL(
              appID: "example", version: "1.0.0", filename: "example.app.tar.bz2"),
          "Download the selected version's stable release asset.")
        try data.write(to: destination)
        progress(Int64(data.count))
      }, command: commands.run, temporaryDirectory: work)
    let version = InstallationFixtures.version(data: data)
    var phases: [AppInstallationPhase] = []
    try await installer.install(
      app: InstallationFixtures.app(version: version), version: version,
      on: InstallationFixtures.device
    ) {
      phases.append($0)
    }
    try InstallationFixtures.require(
      phases.contains(.verifying) && phases.contains(.extracting) && phases.contains(.installing),
      "Report preparation and installation stages.")
    let installed = commands.calls.filter { $0.first == "simctl" }
    try InstallationFixtures.require(
      installed.count == 1 && installed[0].prefix(3) == ["simctl", "install", "device-A"],
      "Install once on the exact target device.")
    try InstallationFixtures.require(
      try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty,
      "Remove the archive and extracted app after installation.")
    try await installer.open(app: InstallationFixtures.app(), on: InstallationFixtures.device)
    try InstallationFixtures.require(
      commands.calls.last == ["simctl", "launch", "device-A", "org.example.App"],
      "Open the installed app on its target device.")
  }

  static func failureAndCleanup() async throws {
    let directory = try InstallationFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = try archiveData(in: directory)
    let work = directory.appending(component: "work")
    for mode in 0..<4 {
      let commands = InstallationCommands(failsInstallation: mode == 3)
      let installer = AppInstaller(
        download: { _, destination, _ in
          if mode == 0 { throw InstallationFixtures.failure("Download failed") }
          var bytes = data
          if mode == 1 { bytes.removeLast() }
          if mode == 2 { bytes[bytes.count - 1] ^= 0xFF }
          try bytes.write(to: destination)
        }, command: commands.run, temporaryDirectory: work)
      do {
        try await installer.install(
          app: InstallationFixtures.app(), version: InstallationFixtures.version(data: data),
          on: InstallationFixtures.device
        ) { _ in }
        throw InstallationFixtures.failure(
          "A failed download, verification, or install must fail the pipeline.")
      } catch {
        if mode < 3 {
          try InstallationFixtures.require(
            commands.calls.isEmpty, "Unverified data must not be extracted or installed.")
        } else {
          try InstallationFixtures.require(
            error.localizedDescription == "Install failed", "Preserve simctl failure diagnostics.")
        }
      }
      try InstallationFixtures.require(
        try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty,
        "Clean temporary files on every failure path.")
    }
  }

  static func perDeviceJobs() async throws {
    let directory = try InstallationFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = try archiveData(in: directory)
    let gate = InstallationDownloadGate(data: data)
    let commands = InstallationCommands()
    let inventory = InstalledAppsStore(load: { _ in [] })
    await inventory.refresh(for: InstallationFixtures.device)
    let store = AppInstallationStore(
      installer: AppInstaller(
        download: { try await gate.download($0, $1, $2) }, command: commands.run,
        temporaryDirectory: directory.appending(component: "work")),
      didInstall: { inventory.recordInstallation(bundleID: $0, deviceID: $1) })
    let version = InstallationFixtures.version(data: data)
    let app = InstallationFixtures.app(version: version)
    let a = InstallationFixtures.device
    let b = SimulatorDevice(id: "device-B", name: a.name, runtime: a.runtime, state: a.state)
    store.install(app: app, version: version, on: a)
    try await gate.waitForCount(1)
    store.install(app: app, version: version, on: a)
    store.install(app: app, version: version, on: b)
    try await gate.waitForCount(2)
    try InstallationFixtures.require(
      await gate.count == 2, "Do not duplicate a job for the same app and device.")
    await gate.report(0, bytes: 100)
    await gate.report(0, bytes: 50)
    try await InstallationFixtures.eventually {
      store.phase(appID: app.id, deviceID: a.id) == .downloading(100)
    }
    await gate.finish(1)
    try await InstallationFixtures.eventually { store.phase(appID: app.id, deviceID: b.id) == nil }
    try InstallationFixtures.require(
      inventory.bundleIDs == [],
      "Installing on another simulator must not alter the selected inventory.")
    store.cancel(appID: app.id, deviceID: a.id)
    try InstallationFixtures.require(
      store.phase(appID: app.id, deviceID: a.id) == .canceling,
      "Keep a canceled operation visible until its cleanup finishes.")
    await gate.finish(0)
    try await InstallationFixtures.eventually { store.phase(appID: app.id, deviceID: a.id) == nil }
    try InstallationFixtures.require(
      store.error(appID: app.id, deviceID: a.id) == nil,
      "Cancellation is not an installation error.")
    store.install(app: app, version: version, on: a)
    try await gate.waitForCount(3)
    await gate.report(0, bytes: 999)
    try await Task.sleep(for: .milliseconds(10))
    try InstallationFixtures.require(
      store.phase(appID: app.id, deviceID: a.id) == .downloading(0),
      "Ignore late progress from an earlier attempt.")
    await gate.finish(2)
    try await InstallationFixtures.eventually { store.phase(appID: app.id, deviceID: a.id) == nil }
    try InstallationFixtures.require(
      inventory.isInstalled(bundleID: app.bundleID, deviceID: a.id) == true,
      "A successful install updates the selected inventory immediately.")
    let installedDevices = commands.calls.filter { $0.prefix(2) == ["simctl", "install"] }.map {
      $0[2]
    }
    try InstallationFixtures.require(
      installedDevices == [b.id, a.id],
      "Cancellation and simulator changes must not retarget an operation.")
    store.open(app: app, on: b)
    try await InstallationFixtures.eventually { store.phase(appID: app.id, deviceID: b.id) == nil }
    try InstallationFixtures.require(
      commands.calls.last == ["simctl", "launch", b.id, app.bundleID],
      "Launch on the requested device.")
  }

  static func cancellationDuringPreparation() async throws {
    let directory = try InstallationFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = try archiveData(in: directory)
    let commands = InstallationCommands(blocksExtraction: true)
    let work = directory.appending(component: "work")
    let store = AppInstallationStore(
      installer: AppInstaller(
        download: { _, destination, _ in
          try data.write(to: destination)
        }, command: commands.run, temporaryDirectory: work))
    let app = InstallationFixtures.app()
    let device = InstallationFixtures.device
    store.install(app: app, version: InstallationFixtures.version(data: data), on: device)
    try InstallationFixtures.require(
      await Task.detached { commands.waitForStart() }.value,
      "Start preparation before canceling.")
    store.cancel(appID: app.id, deviceID: device.id)
    commands.finish.signal()
    try await InstallationFixtures.eventually {
      store.phase(appID: app.id, deviceID: device.id) == nil
    }
    try InstallationFixtures.require(
      !commands.calls.contains { $0.first == "simctl" },
      "A canceled preparation must not install anything.")
    try InstallationFixtures.require(
      try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty,
      "Remove canceled preparation files.")
  }

  static func installingCannotBeCanceled() async throws {
    let directory = try InstallationFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = try archiveData(in: directory)
    let commands = InstallationCommands(blocksInstallation: true)
    var installed = false
    let store = AppInstallationStore(
      installer: AppInstaller(
        download: { _, destination, _ in
          try data.write(to: destination)
        }, command: commands.run, temporaryDirectory: directory.appending(component: "work")),
      didInstall: { _, _ in installed = true })
    let app = InstallationFixtures.app()
    let device = InstallationFixtures.device
    store.install(app: app, version: InstallationFixtures.version(data: data), on: device)
    try InstallationFixtures.require(
      await Task.detached { commands.waitForStart() }.value,
      "Wait until simctl starts installing.")
    store.cancel(appID: app.id, deviceID: device.id)
    try InstallationFixtures.require(
      store.phase(appID: app.id, deviceID: device.id) == .installing,
      "Once simctl starts, allow installation to finish.")
    commands.finish.signal()
    try await InstallationFixtures.eventually {
      store.phase(appID: app.id, deviceID: device.id) == nil
    }
    try InstallationFixtures.require(
      installed, "Record a confirmed installation even after a late cancellation request.")
  }

  static func stoppedDevice() async throws {
    let stopped = SimulatorDevice(id: "stopped", name: "iPhone", runtime: "27.0", state: "Shutdown")
    let commands = InstallationCommands()
    let store = AppInstallationStore(
      installer: AppInstaller(
        download: { _, _, _ in throw InstallationFixtures.failure("Unexpected download") },
        command: commands.run))
    let app = InstallationFixtures.app()
    store.install(app: app, version: app.latestVersion, on: stopped)
    try await InstallationFixtures.eventually {
      store.phase(appID: app.id, deviceID: stopped.id) == nil
    }
    try InstallationFixtures.require(
      store.error(appID: app.id, deviceID: stopped.id)
        == SimulatorApplicationsError.notRunning.localizedDescription && commands.calls.isEmpty,
      "A stopped simulator must fail before downloading or running simctl.")
    store.open(app: app, on: stopped)
    try await InstallationFixtures.eventually {
      store.phase(appID: app.id, deviceID: stopped.id) == nil
    }
    try InstallationFixtures.require(
      store.error(appID: app.id, deviceID: stopped.id) != nil && commands.calls.isEmpty,
      "Report launch failures without claiming success.")
  }

  static func archiveData(in directory: URL) throws -> Data {
    try Data(
      contentsOf: InstallationFixtures.archive(InstallationFixtures.entries(), in: directory))
  }
}

private final class InstallationCommands: @unchecked Sendable {
  let started = DispatchSemaphore(value: 0)
  let finish = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var recorded: [[String]] = []
  private let blocksExtraction: Bool
  private let blocksInstallation: Bool
  private let failsInstallation: Bool

  init(
    blocksExtraction: Bool = false, blocksInstallation: Bool = false,
    failsInstallation: Bool = false
  ) {
    self.blocksExtraction = blocksExtraction
    self.blocksInstallation = blocksInstallation
    self.failsInstallation = failsInstallation
  }

  var calls: [[String]] { lock.withLock { recorded } }

  func waitForStart() -> Bool { started.wait(timeout: .now() + 5) == .success }

  func run(_ executable: String, _ arguments: [String]) throws -> Data {
    try InstallationFixtures.require(
      !Thread.isMainThread, "Package commands and simctl must not block the UI.")
    lock.withLock { recorded.append(arguments) }
    if executable == "/usr/bin/tar" {
      if blocksExtraction && arguments.first == "-tjf" { try block() }
      return try Command.run(executable, arguments: arguments)
    }
    try InstallationFixtures.require(
      executable == "/usr/bin/xcrun" && arguments.first == "simctl",
      "Use the common simctl wrapper.")
    if arguments[1] == "install" {
      try InstallationFixtures.require(
        FileManager.default.fileExists(atPath: arguments[3] + "/Info.plist"),
        "Keep the verified app until simctl finishes.")
      if blocksInstallation { try block() }
      if failsInstallation { throw InstallationFixtures.failure("Install failed") }
    }
    return Data("org.example.App: 1234\n".utf8)
  }

  private func block() throws {
    started.signal()
    try InstallationFixtures.require(
      finish.wait(timeout: .now() + 5) == .success, "Release the blocked command.")
  }
}

private actor InstallationDownloadGate {
  private let data: Data
  private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
  private var progress: [AppDownload.Progress] = []
  var count: Int { progress.count }

  init(data: Data) { self.data = data }

  func download(_ url: URL, _ destination: URL, _ callback: @escaping AppDownload.Progress)
    async throws
  {
    let index = count
    progress.append(callback)
    await withCheckedContinuation { pending[index] = $0 }
    try data.write(to: destination)
  }

  func finish(_ index: Int) { pending.removeValue(forKey: index)?.resume() }
  func report(_ index: Int, bytes: Int64) { progress[index](bytes) }

  func waitForCount(_ expected: Int) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while count < expected {
      guard ContinuousClock.now < deadline else {
        throw InstallationFixtures.failure("A download did not start.")
      }
      try await Task.sleep(for: .milliseconds(1))
    }
  }
}
