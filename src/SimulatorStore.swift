import Foundation
import Observation

@MainActor
@Observable
final class SimulatorStore {
  private(set) var result: Result<SimulatorDiscovery, Error>?
  private(set) var isChecking = false
  private(set) var selectedDeviceID: String?
  private(set) var startingDeviceIDs: Set<String> = []
  private(set) var shuttingDownDeviceIDs: Set<String> = []
  var startError: String?
  var shutdownError: String?

  @ObservationIgnored
  private let discover: @MainActor () async throws -> SimulatorDiscovery
  @ObservationIgnored
  private let boot: @Sendable (String) async throws -> Void
  @ObservationIgnored
  private let shutdown: @Sendable (String) async throws -> Void
  @ObservationIgnored
  private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    discover: @escaping @MainActor () async throws -> SimulatorDiscovery,
    shutdown: @escaping @Sendable (String) async throws -> Void = {
      try await SimulatorControl.shutdown($0)
    },
    boot: @escaping @Sendable (String) async throws -> Void
  ) {
    self.discover = discover
    self.boot = boot
    self.shutdown = shutdown
  }

  private var snapshot: SimulatorDiscovery? {
    guard case .success(let discovery) = result else { return nil }
    return discovery
  }

  var discovery: SimulatorDiscovery? {
    guard let snapshot else { return nil }
    return SimulatorDiscovery(
      developerDirectory: snapshot.developerDirectory,
      devices: snapshot.devices.map { device in
        let state: String
        if shuttingDownDeviceIDs.contains(device.id) {
          state = "Shutting Down"
        } else if startingDeviceIDs.contains(device.id) {
          state = "Booting"
        } else {
          return device
        }
        return SimulatorDevice(
          id: device.id, name: device.name, runtime: device.runtime, state: state)
      })
  }

  var selectedDevice: SimulatorDevice? {
    discovery?.devices.first { $0.id == selectedDeviceID }
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
        let devices = self.discovery?.devices ?? []
        selectedDeviceID =
          devices.first(where: { $0.state == "Booted" })?.id ?? devices.first?.id
      }
    } catch is CancellationError {
    } catch {
      result = .failure(error)
    }
  }

  @discardableResult
  func startDevice(_ id: String) async -> Bool {
    guard let device = snapshot?.devices.first(where: { $0.id == id }),
      device.canStart,
      !shuttingDownDeviceIDs.contains(device.id),
      startingDeviceIDs.insert(device.id).inserted
    else { return false }
    startError = nil
    defer { startingDeviceIDs.remove(device.id) }
    do {
      try await boot(device.id)
      try await refreshAfterControl()
      return snapshot?.devices.contains(where: { $0.id == device.id && $0.state == "Booted" })
        == true
    } catch is CancellationError {
      return false
    } catch {
      startError = String(
        localized: "Couldn’t start \(device.name).\n\(error.localizedDescription)")
      return false
    }
  }

  @discardableResult
  func shutdownDevice(_ id: String) -> Task<Bool, Never>? {
    guard let device = snapshot?.devices.first(where: { $0.id == id }), device.canShutdown,
      !startingDeviceIDs.contains(device.id), shuttingDownDeviceIDs.insert(device.id).inserted
    else { return nil }
    shutdownError = nil
    return Task { [self] in
      defer { shuttingDownDeviceIDs.remove(device.id) }
      do {
        try Task.checkCancellation()
        try await shutdown(device.id)
        try await refreshAfterControl()
        return snapshot?.devices.contains(where: { $0.id == device.id && $0.state == "Shutdown" })
          == true
      } catch is CancellationError {
        return false
      } catch {
        shutdownError = String(
          localized: "Couldn’t shut down \(device.name).\n\(error.localizedDescription)")
        return false
      }
    }
  }

  private func refreshAfterControl() async throws {
    try Task.checkCancellation()
    // A scan begun before the operation completed may contain the previous power state.
    if isChecking { await waitForRefresh() }
    try Task.checkCancellation()
    await refresh()
    try Task.checkCancellation()
  }

  private func waitForRefresh() async {
    await withCheckedContinuation { continuation in
      refreshWaiters.append(continuation)
    }
  }
}
