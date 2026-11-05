import Foundation
import Observation

@MainActor
@Observable
final class SimulatorStore {
  private(set) var result: Result<SimulatorDiscovery, Error>?
  private(set) var isChecking = false
  private(set) var selectedDeviceID: String?
  private(set) var startingDeviceIDs: Set<String> = []
  var startError: String?

  @ObservationIgnored
  private let discover: @MainActor () async throws -> SimulatorDiscovery
  @ObservationIgnored
  private let boot: @Sendable (String) async throws -> Void
  @ObservationIgnored
  private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    discover: @escaping @MainActor () async throws -> SimulatorDiscovery,
    boot: @escaping @Sendable (String) async throws -> Void
  ) {
    self.discover = discover
    self.boot = boot
  }

  var discovery: SimulatorDiscovery? {
    guard case .success(let discovery) = result else { return nil }
    return discovery
  }

  var selectedDevice: SimulatorDevice? {
    discovery?.devices.first { $0.id == selectedDeviceID }
  }

  var isStartingSelectedDevice: Bool {
    guard let selectedDeviceID else { return false }
    return startingDeviceIDs.contains(selectedDeviceID)
  }

  func selectDevice(_ id: String) {
    guard discovery?.devices.contains(where: { $0.id == id }) == true else { return }
    selectedDeviceID = id
  }

  func refresh() async {
    guard !isChecking else {
      await waitForRefresh()
      return
    }
    isChecking = true
    defer {
      isChecking = false
      let waiters = refreshWaiters
      refreshWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
    do {
      let discovery = try await discover()
      try Task.checkCancellation()
      result = .success(discovery)
      if !discovery.devices.contains(where: { $0.id == selectedDeviceID }) {
        selectedDeviceID =
          discovery.devices.first(where: { $0.state == "Booted" })?.id
          ?? discovery.devices.first?.id
      }
    } catch is CancellationError {
    } catch {
      result = .failure(error)
    }
  }

  @discardableResult
  func startSelectedDevice() async -> Bool {
    guard let device = selectedDevice,
      device.canStart,
      startingDeviceIDs.insert(device.id).inserted
    else { return false }
    startError = nil
    defer { startingDeviceIDs.remove(device.id) }
    do {
      try await boot(device.id)
      try Task.checkCancellation()
      // An inventory scan begun before boot completed may still report Shutdown.
      if isChecking { await waitForRefresh() }
      try Task.checkCancellation()
      await refresh()
      try Task.checkCancellation()
      return discovery?.devices.contains(where: { $0.id == device.id && $0.state == "Booted" })
        == true
    } catch is CancellationError {
      return false
    } catch {
      startError = String(
        localized: "Couldn’t start \(device.name).\n\(error.localizedDescription)")
      return false
    }
  }

  private func waitForRefresh() async {
    await withCheckedContinuation { continuation in
      refreshWaiters.append(continuation)
    }
  }
}
