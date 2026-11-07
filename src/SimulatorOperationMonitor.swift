import Foundation
import Observation

@MainActor
@Observable
final class SimulatorOperationMonitor {
  struct Prompt: Identifiable, Equatable {
    let id: UUID
    let device: SimulatorDevice
  }

  typealias Wait = @Sendable () async throws -> Void

  private var stalled: [Prompt] = []
  var prompt: Prompt? { stalled.first }

  @ObservationIgnored private let wait: Wait
  @ObservationIgnored private var active:
    [UUID: (device: SimulatorDevice, task: Task<Void, Never>)] = [:]
  @ObservationIgnored private var mutedDevices: Set<String> = []

  init(wait: @escaping Wait = { try await Task.sleep(for: .seconds(30)) }) {
    self.wait = wait
  }

  func begin(on device: SimulatorDevice) -> UUID {
    let id = UUID()
    guard device.state == "Booted" else { return id }
    let wait = wait
    let task = Task { [weak self] in
      do {
        try await wait()
        try Task.checkCancellation()
      } catch { return }
      guard let self, active[id] != nil, !mutedDevices.contains(device.id) else { return }
      stalled.append(Prompt(id: id, device: device))
    }
    active[id] = (device, task)
    return id
  }

  func end(_ id: UUID) {
    guard let operation = active.removeValue(forKey: id) else { return }
    operation.task.cancel()
    stalled.removeAll { $0.id == id }
    if !active.values.contains(where: { $0.device.id == operation.device.id }) {
      mutedDevices.remove(operation.device.id)
    }
  }

  func keepWaiting(_ prompt: Prompt) {
    guard stalled.contains(where: { $0.id == prompt.id }) else { return }
    mutedDevices.insert(prompt.device.id)
    stalled.removeAll { $0.device.id == prompt.device.id }
  }

  func stop(deviceID: String) {
    for id in active.keys.filter({ active[$0]?.device.id == deviceID }) {
      end(id)
    }
  }

  func synchronize(with devices: [SimulatorDevice]) {
    let booted = Set(devices.filter { $0.state == "Booted" }.map(\.id))
    for deviceID in Set(active.values.map { $0.device.id }).subtracting(booted) {
      stop(deviceID: deviceID)
    }
  }
}
