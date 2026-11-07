import Foundation

@main
@MainActor
struct SimulatorStoreTests {
  static func main() async {
    do {
      try await selectionAndRefresh()
      try await startingAndSelectionChanges()
      try await independentStarts()
      try await overlappingRefresh()
      try await startFailureAndCancellation()
      try await startupRequiresConfirmedReadiness()
      try await failedBootAfterBootedPoll()
      try await shutdownTests()
      print("PASS: simulator selection, refresh, concurrent startup, errors, and cancellation.")
    } catch {
      FileHandle.standardError.write(
        Data("Simulator store test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  static func selectionAndRefresh() async throws {
    let fixture = Inventory([device("A"), device("B", state: .booted)])
    let store = SimulatorStore(discover: fixture.scan, boot: { _ in })
    await store.refresh()
    try require(store.selectedDeviceID == "B", "Prefer an already booted simulator initially.")
    store.selectDevice("A")
    store.selectDevice("missing")
    await store.refresh()
    try require(store.selectedDeviceID == "A", "Keep an existing selection across refreshes.")
    fixture.error = failure("Discovery failed")
    await store.refresh()
    try require(store.discovery == nil, "A discovery error must not expose a stale inventory.")
    try require(store.selectedDeviceID == "A", "Keep the selection through a discovery error.")
    fixture.error = nil
    fixture.devices = [device("C"), device("B", state: .booted)]
    await store.refresh()
    try require(
      store.selectedDeviceID == "B", "Replace a disappeared selection with a booted device.")
    fixture.devices = []
    await store.refresh()
    try require(
      store.selectedDevice == nil && store.selectedDeviceID == nil, "Clear an empty selection.")
    fixture.devices = [device("D"), device("E")]
    await store.refresh()
    try require(store.selectedDeviceID == "D", "Choose the first device when none is booted.")
  }

  static func startingAndSelectionChanges() async throws {
    let fixture = Inventory([device("A"), device("B")])
    let probe = PowerProbe()
    let store = SimulatorStore(discover: fixture.scan, boot: { try await probe.run($0) })
    await store.refresh()
    let startup = Task { await store.startDevice("A") }
    try await eventually { await probe.calls == ["A"] }
    try require(
      store.selectedDevice?.state == .booting, "Expose startup progress for the selected device.")
    try require(
      await store.startDevice("A") == false, "A duplicate start must not report success.")
    try require(await probe.calls == ["A"], "Repeated clicks must not start a device twice.")
    store.selectDevice("B")
    try require(
      store.selectedDevice?.state != .booting, "Startup progress must follow its own device.")
    try require(
      store.startingDeviceIDs == ["A"], "Changing selection must not lose startup tracking.")
    fixture.devices = [device("A", state: .booted), device("B")]
    await probe.finish()
    try require(
      await startup.value, "A successful boot confirmed by inventory should report success.")
    try require(
      store.selectedDeviceID == "B", "Startup completion must preserve a later selection.")
    try require(
      store.discovery?.devices.first?.state == .booted,
      "Read startup state from a fresh inventory.")
    try require(store.startingDeviceIDs.isEmpty, "Clear progress after startup.")
    try require(fixture.calls == 2, "Refresh the inventory after startup.")
    store.selectDevice("A")
    try require(
      await store.startDevice("A") == false, "An ignored start must not report success.")
    try require(await probe.calls == ["A"], "An already booted device needs no boot command.")
  }

  static func overlappingRefresh() async throws {
    let fixture = Inventory([device("A")])
    let probe = PowerProbe()
    let store = SimulatorStore(discover: fixture.scan, boot: { try await probe.run($0) })
    await store.refresh()
    let startup = Task { await store.startDevice("A") }
    try await eventually { await probe.calls == ["A"] }
    fixture.deferNextScan = true
    let refresh = Task { await store.refresh() }
    try await eventually { fixture.pendingScan != nil }
    let coalesced = Task { await store.refresh() }
    await Task.yield()
    try require(fixture.calls == 2, "Concurrent refreshes should share one scan.")
    await probe.finish()
    fixture.devices = [device("A", state: .booted)]
    fixture.finishScan(with: [device("A")])
    await refresh.value
    await coalesced.value
    try require(
      await startup.value, "Fresh readiness after an overlapping scan should report success.")
    try require(
      fixture.calls == 3, "Startup must request a scan newer than any in-flight inventory.")
    try require(
      store.selectedDevice?.state == .booted, "An old scan must not hide successful startup.")
    try require(
      !store.isChecking && store.selectedDevice?.state != .booting, "All progress must finish.")
  }

  static func independentStarts() async throws {
    let fixture = Inventory([device("A"), device("B", state: .booting)])
    let probe = PowerProbe()
    let store = SimulatorStore(discover: fixture.scan, boot: { try await probe.run($0) })
    await store.refresh()
    let first = Task { await store.startDevice("A") }
    try await eventually { await probe.calls == ["A"] }
    store.selectDevice("B")
    let second = Task { await store.startDevice("B") }
    try await eventually { await probe.calls == ["A", "B"] }
    try require(
      store.startingDeviceIDs == ["A", "B"], "Track each simulator's startup separately.")
    fixture.devices = [device("A", state: .booted), device("B", state: .booting)]
    await probe.finish("A")
    try require(await first.value, "Confirm the first simulator's startup independently.")
    try require(
      store.startingDeviceIDs == ["B"], "One startup must not clear another device's progress.")
    try require(
      store.selectedDevice?.state == .booting,
      "Keep progress for the currently selected simulator.")
    fixture.devices = [device("A", state: .booted), device("B", state: .booted)]
    await probe.finish("B")
    try require(await second.value, "Confirm the second simulator's startup independently.")
    try require(
      store.selectedDeviceID == "B" && store.startingDeviceIDs.isEmpty,
      "Finish both independent startups.")
  }

  static func startFailureAndCancellation() async throws {
    for cancelled in [false, true] {
      let fixture = Inventory([device("A")])
      let store = SimulatorStore(discover: fixture.scan) { _ in
        if cancelled { throw CancellationError() }
        throw failure("Could not start this simulator")
      }
      await store.refresh()
      try require(
        await store.startDevice("A") == false, "A failed or cancelled start must return false."
      )
      try require(
        store.startingDeviceIDs.isEmpty, "A failed or cancelled start must clear progress.")
      try require(
        store.selectedDevice?.state == .shutdown, "A failed command cannot imply Booted.")
      try require(fixture.calls == 1, "A failed boot should not imply a successful refresh.")
      if cancelled {
        try require(store.startError == nil, "Keep cancellation silent.")
      } else {
        try require(
          store.startError?.contains("iPhone A") == true
            && store.startError?.contains("Could not start this simulator") == true,
          "Identify the failed simulator and preserve the boot diagnostic.")
      }
    }
    for state in [SimulatorState.shuttingDown, .unknown] {
      let fixture = Inventory([device("A", state: state)])
      let store = SimulatorStore(discover: fixture.scan) { _ in
        throw failure("Do not start a device in an unavailable state")
      }
      await store.refresh()
      try require(
        await store.startDevice("A") == false && store.startError == nil,
        "Unknown and shutting-down devices must not receive a boot command.")
    }
  }

  static func startupRequiresConfirmedReadiness() async throws {
    for refreshedDevices in [[device("A")], [device("A", state: .booting)], []] {
      let fixture = Inventory([device("A")])
      let probe = PowerProbe()
      let store = SimulatorStore(discover: fixture.scan, boot: { try await probe.run($0) })
      await store.refresh()
      let startup = Task { await store.startDevice("A") }
      try await eventually { await probe.calls == ["A"] }
      fixture.devices = refreshedDevices
      await probe.finish()
      try require(
        await startup.value == false,
        "A successful command alone cannot confirm a missing or unready simulator.")
    }
  }

  static func failedBootAfterBootedPoll() async throws {
    let fixture = Inventory([device("A"), device("B")])
    let probe = PowerProbe()
    let store = SimulatorStore(discover: fixture.scan, boot: { try await probe.run($0) })
    await store.refresh()
    let startup = Task { await store.startDevice("A") }
    try await eventually { await probe.calls == ["A"] }
    store.selectDevice("B")
    fixture.devices = [device("A", state: .booted), device("B")]
    await store.refresh()
    await probe.fail("A", error: failure("Boot readiness failed"))
    try require(
      await startup.value == false, "Boot failure must override an intermediate Booted snapshot.")
    try require(
      store.selectedDeviceID == "B", "A startup error must preserve the user's later selection.")
    try require(
      store.startError?.contains("iPhone A") == true
        && store.startError?.contains("Boot readiness failed") == true,
      "Attribute the error to the device that was started, even after selection changes.")
  }

  static func device(_ id: String, state: SimulatorState = .shutdown) -> SimulatorDevice {
    SimulatorDevice(id: id, name: "iPhone \(id)", runtime: "27.0", state: state)
  }

  static func eventually(_ condition: () async -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))
    while !(await condition()) {
      guard clock.now < deadline else { throw failure("Timed out waiting for an async operation") }
      await Task.yield()
    }
  }

  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw failure(message) }
  }

  nonisolated static func failure(_ message: String) -> NSError {
    NSError(domain: "SimulatorStoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  @MainActor
  final class Inventory {
    var devices: [SimulatorDevice]
    var error: Error?
    var calls = 0
    var deferNextScan = false
    var pendingScan: CheckedContinuation<SimulatorDiscovery, Error>?

    init(_ devices: [SimulatorDevice]) { self.devices = devices }

    func scan() async throws -> SimulatorDiscovery {
      calls += 1
      if let error { throw error }
      if deferNextScan {
        deferNextScan = false
        return try await withCheckedThrowingContinuation { pendingScan = $0 }
      }
      return snapshot(devices)
    }

    func finishScan(with devices: [SimulatorDevice]) {
      let continuation = pendingScan
      pendingScan = nil
      continuation?.resume(returning: snapshot(devices))
    }

    private func snapshot(_ devices: [SimulatorDevice]) -> SimulatorDiscovery {
      SimulatorDiscovery(
        developerDirectory: URL(fileURLWithPath: "/Xcode.app/Contents/Developer"), devices: devices)
    }
  }

  actor PowerProbe {
    private(set) var calls: [String] = []
    private var continuations: [String: CheckedContinuation<Void, Error>] = [:]

    func run(_ id: String) async throws {
      calls.append(id)
      try await withCheckedThrowingContinuation { continuations[id] = $0 }
    }

    func finish(_ id: String = "A") {
      continuations.removeValue(forKey: id)?.resume()
    }

    func fail(_ id: String, error: Error) {
      continuations.removeValue(forKey: id)?.resume(throwing: error)
    }
  }
}
