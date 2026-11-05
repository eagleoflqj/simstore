import Foundation

@main
@MainActor
struct InstalledAppsStoreTests {
  static func main() async {
    do {
      try await filteringAndRefresh()
      try await switchingDevices()
      try await staleErrors()
      try await cancellationAndCoalescing()
      try await refreshedDeviceState()
      try await recordingInstallationDuringRefresh()
      try await retainInstalledAppsForCurrentVisit()
      print(
        "PASS: per-device installed apps, filtering, stale responses, errors, and cancellation.")
    } catch {
      FileHandle.standardError.write(
        Data("Installed apps store test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  static func filteringAndRefresh() async throws {
    let probe = InventoryProbe()
    let store = InstalledAppsStore(load: { try await probe.load($0) })
    let selected = device("A")
    let catalog = catalog()
    try require(store.discoverableApps(in: catalog, for: "A") == nil, "Unknown is not uninstalled.")
    let initial = Task { await store.refresh(for: selected) }
    try await eventually { await probe.calls.count == 1 }
    try require(
      store.deviceID == "A" && store.bundleIDs == nil && store.isLoading,
      "A pending query must not expose an empty installation set.")
    await probe.finish(0, with: .success(["io.example.Installed", "io.example.UNKNOWN"]))
    await initial.value
    try require(
      store.discoverableApps(in: catalog, for: "A")?.map(\.id) == ["available"],
      "Exclude installed apps by their case-insensitive Bundle ID, regardless of version.")
    try require(
      store.discoverableApps(in: catalog, for: "B") == nil,
      "A snapshot may only filter its own simulator.")
    let failed = Task { await store.refresh(for: selected) }
    try await eventually { await probe.calls.count == 2 }
    try require(store.bundleIDs == nil, "Refreshing must clear a snapshot that may be stale.")
    await probe.finish(1, with: .failure(failure("Cannot read installed apps")))
    await failed.value
    try require(
      store.error == "Cannot read installed apps" && !store.isLoading && store.bundleIDs == nil,
      "A failed query must report an error without claiming no apps are installed.")
    let retry = Task { await store.refresh(for: selected) }
    try await eventually { await probe.calls.count == 3 }
    await probe.finish(2, with: .success([]))
    await retry.value
    try require(
      store.error == nil && store.bundleIDs == []
        && store.discoverableApps(in: catalog, for: "A")?.count == catalog.apps.count,
      "A confirmed empty installation set exposes the full catalog and clears the prior error.")
    let externalInstall = Task { await store.refresh(for: selected) }
    try await eventually { await probe.calls.count == 4 }
    await probe.finish(3, with: .success(["io.example.Available"]))
    await externalInstall.value
    try require(
      store.discoverableApps(in: catalog, for: "A")?.map(\.id) == ["installed", "case-variant"],
      "A later query must reflect apps installed outside SimStore.")
  }

  static func switchingDevices() async throws {
    let probe = InventoryProbe()
    let store = InstalledAppsStore(load: { try await probe.load($0) })
    let a = Task { await store.refresh(for: device("A")) }
    try await eventually { await probe.calls.count == 1 }
    let b = Task { await store.refresh(for: device("B")) }
    try await eventually { await probe.calls.count == 2 }
    try require(
      store.deviceID == "B" && store.bundleIDs == nil && store.isLoading,
      "Two identically named simulators must keep separate installation inventories.")
    await probe.finish(1, with: .success(["io.example.B"]))
    await b.value
    await probe.finish(0, with: .success(["io.example.A"]))
    await a.value
    try require(
      store.deviceID == "B" && store.bundleIDs == ["io.example.B"] && !store.isLoading,
      "A late response from the previous simulator must not replace the current snapshot.")
    let oldA = Task { await store.refresh(for: device("A")) }
    try await eventually { await probe.calls.count == 3 }
    let newB = Task { await store.refresh(for: device("B")) }
    try await eventually { await probe.calls.count == 4 }
    await probe.finish(2, with: .success(["io.example.Stale"]))
    await oldA.value
    try require(
      store.deviceID == "B" && store.bundleIDs == nil && store.isLoading,
      "Completing an old query must not clear the new simulator's loading state.")
    await probe.finish(3, with: .success(["io.example.New"]))
    await newB.value
  }

  static func staleErrors() async throws {
    let probe = InventoryProbe()
    let store = InstalledAppsStore(load: { try await probe.load($0) })
    let a = Task { await store.refresh(for: device("A")) }
    try await eventually { await probe.calls.count == 1 }
    let b = Task { await store.refresh(for: device("B")) }
    try await eventually { await probe.calls.count == 2 }
    await probe.finish(1, with: .success(["io.example.B"]))
    await b.value
    await probe.finish(0, with: .failure(failure("Old simulator failed")))
    await a.value
    try require(
      store.error == nil && store.bundleIDs == ["io.example.B"],
      "A stale simulator's error must not hide the current simulator's valid inventory.")
  }

  static func cancellationAndCoalescing() async throws {
    let probe = InventoryProbe()
    let store = InstalledAppsStore(load: { try await probe.load($0) })
    let selected = device("A")
    let first = Task { await store.refresh(for: selected) }
    try await eventually { await probe.calls.count == 1 }
    var joined = false
    let second = Task {
      joined = true
      await store.refresh(for: selected)
    }
    try await eventually { joined }
    try require(await probe.calls.count == 1, "Coalesce simultaneous queries of the same device.")
    first.cancel()
    await probe.finish(0, with: .success(["io.example.Cancelled"]))
    await first.value
    try await eventually { await probe.calls.count == 2 }
    try require(
      store.isLoading && store.bundleIDs == nil && store.error == nil,
      "An active joining caller must retry after the canceled query without showing a false result."
    )
    await probe.finish(1, with: .success(["io.example.Active"]))
    await second.value
    try require(
      store.bundleIDs == ["io.example.Active"], "The active retry must produce its result.")
    let canceled = Task { await store.refresh(for: selected) }
    try await eventually { await probe.calls.count == 3 }
    canceled.cancel()
    await probe.finish(2, with: .success(["io.example.Cancelled"]))
    await canceled.value
    try require(
      !store.isLoading && store.bundleIDs == nil && store.error == nil,
      "Canceling the only caller must finish silently and leave the installation state unknown.")
    let retry = Task { await store.refresh(for: selected) }
    try await eventually { await probe.calls.count == 4 }
    await probe.finish(3, with: .success([]))
    await retry.value
    try require(store.bundleIDs == [], "A canceled query must not prevent a later retry.")
  }

  static func refreshedDeviceState() async throws {
    let probe = InventoryProbe()
    let store = InstalledAppsStore(load: { try await probe.load($0) })
    let stopped = Task { await store.refresh(for: device("A", state: "Shutdown")) }
    try await eventually { await probe.calls.count == 1 }
    let booted = Task { await store.refresh(for: device("A", state: "Booted")) }
    try await eventually { await probe.calls.count == 2 }
    await probe.finish(1, with: .success(["io.example.New"]))
    await booted.value
    await probe.finish(0, with: .success(["io.example.Old"]))
    await stopped.value
    try require(
      store.bundleIDs == ["io.example.New"],
      "A device state change must query afresh rather than join an older shutdown query.")
  }

  static func device(_ id: String, state: String = "Booted") -> SimulatorDevice {
    SimulatorDevice(id: id, name: "iPhone 17 Pro", runtime: "27.0", state: state)
  }

  static func recordingInstallationDuringRefresh() async throws {
    let probe = InventoryProbe()
    let store = InstalledAppsStore(load: { try await probe.load($0) })
    let first = Task { await store.refresh(for: device("A")) }
    try await eventually { await probe.calls.count == 1 }
    store.recordInstallation(bundleID: "org.example.WrongDevice", deviceID: "B")
    store.recordInstallation(bundleID: "org.example.New", deviceID: "A")
    try require(
      store.bundleIDs == nil,
      "An installation must not turn an unknown inventory into a complete snapshot.")
    await probe.finish(0, with: .success([]))
    await first.value
    try require(
      store.bundleIDs == ["org.example.New"],
      "Merge successful installs into an older in-flight inventory response.")
    try require(
      store.isInstalled(bundleID: "org.example.NEW", deviceID: "A") == true,
      "Match installed bundle IDs without case sensitivity.")
    let next = Task { await store.refresh(for: device("A")) }
    try await eventually { await probe.calls.count == 2 }
    await probe.finish(1, with: .success([]))
    await next.value
    try require(
      store.bundleIDs == [], "A later authoritative refresh must reflect external uninstalls.")
  }

  static func catalog() -> AppCatalog {
    let version = CatalogVersion(
      version: "1.0.0", minSimulatorOS: "16.0", sha256: String(repeating: "a", count: 64),
      size: 1000, revision: String(repeating: "b", count: 40),
      recipeRevision: String(repeating: "c", count: 40), time: 1_793_544_257)
    let apps = [
      ("installed", "io.example.Installed"), ("available", "io.example.Available"),
      ("case-variant", "io.example.Unknown"),
    ].map { id, bundleID in
      CatalogApp(
        id: id, name: "Example", bundleID: bundleID,
        repository: URL(string: "https://github.com/example/app")!, license: "MIT",
        description: ["en": "An example app."], categories: ["utilities"], versions: [version])
    }
    return AppCatalog(schemaVersion: 1, apps: apps)
  }

  static func retainInstalledAppsForCurrentVisit() async throws {
    let current = catalog()
    let store = InstalledAppsStore(load: { _ in ["io.example.Installed", "io.example.Available"] })
    await store.refresh(for: device("A"))
    try require(
      store.discoverableApps(in: current, for: "A")?.map(\.id) == ["case-variant"],
      "Hide apps installed before this visit.")
    store.recordInstallation(bundleID: "io.example.AVAILABLE", deviceID: "A")
    try require(
      store.discoverableApps(in: current, for: "A")?.map(\.id) == ["available", "case-variant"],
      "Keep newly installed apps in their original catalog order.")
    try require(
      store.isInstalled(bundleID: "io.example.Available", deviceID: "A") == true,
      "The retained card must offer Open.")
    store.removeRecentInstallation(bundleID: "io.example.Available", deviceID: "B")
    try require(
      store.discoverableApps(in: current, for: "A")?.map(\.id) == ["available", "case-variant"],
      "Opening on another device must not remove this device's card.")
    await store.refresh(for: device("A"))
    try require(
      store.discoverableApps(in: current, for: "A")?.map(\.id) == ["available", "case-variant"],
      "Automatic inventory refresh must retain the current visit.")
    store.removeRecentInstallation(bundleID: "io.example.AVAILABLE", deviceID: "A")
    try require(
      store.discoverableApps(in: current, for: "A")?.map(\.id) == ["case-variant"],
      "Remove a successfully opened app from the current visit.")
    store.recordInstallation(bundleID: "io.example.Available", deviceID: "A")
    store.clearRecentInstallations()
    try require(
      store.discoverableApps(in: current, for: "A")?.map(\.id) == ["case-variant"],
      "Explicit catalog refresh clears retained installations.")
    store.recordInstallation(bundleID: "io.example.Available", deviceID: "A")
    await store.refresh(for: device("B"))
    await store.refresh(for: device("A"))
    try require(
      store.discoverableApps(in: current, for: "A")?.map(\.id) == ["case-variant"],
      "Switching simulators begins a new visit.")
  }

  static func eventually(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !(await condition()) {
      guard ContinuousClock.now < deadline else { throw failure("An async operation timed out.") }
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw failure(message) }
  }

  static func failure(_ message: String) -> NSError {
    NSError(
      domain: "InstalledAppsStoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

private actor InventoryProbe {
  private(set) var calls: [SimulatorDevice] = []
  private var pending: [Int: CheckedContinuation<Set<String>, Error>] = [:]

  func load(_ device: SimulatorDevice) async throws -> Set<String> {
    let index = calls.count
    calls.append(device)
    return try await withCheckedThrowingContinuation { pending[index] = $0 }
  }

  func finish(_ index: Int, with result: Result<Set<String>, Error>) {
    pending.removeValue(forKey: index)?.resume(with: result)
  }
}
