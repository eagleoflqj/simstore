import Foundation
import Observation

@MainActor
@Observable
final class InstalledAppsStore {
  private(set) var deviceID: String?
  private(set) var bundleIDs: Set<String>?
  private(set) var isLoading = false
  private(set) var error: String?

  @ObservationIgnored
  private let load: @Sendable (SimulatorDevice) async throws -> Set<String>
  @ObservationIgnored
  private var selectedDevice: SimulatorDevice?
  @ObservationIgnored
  private var request: Request?

  init(
    load: @escaping @Sendable (SimulatorDevice) async throws -> Set<String> = {
      try await SimulatorApplications.installedBundleIDs(on: $0)
    }
  ) {
    self.load = load
  }

  func uninstalledApps(in catalog: AppCatalog, for deviceID: String) -> [CatalogApp]? {
    guard self.deviceID == deviceID, let bundleIDs else { return nil }
    let installed = Set(bundleIDs.map { $0.lowercased() })
    return catalog.apps.filter { !installed.contains($0.bundleID.lowercased()) }
  }

  func refresh(for device: SimulatorDevice) async {
    guard !Task.isCancelled else { return }
    if let pending = request, pending.device == device {
      let ownerWasCancelled = await withCheckedContinuation { pending.waiters.append($0) }
      if ownerWasCancelled && !Task.isCancelled && selectedDevice == device {
        await refresh(for: device)
      }
      return
    }
    let pending = Request(device: device)
    request = pending
    selectedDevice = device
    deviceID = device.id
    bundleIDs = nil
    error = nil
    isLoading = true
    defer {
      if request === pending {
        request = nil
        isLoading = false
      }
      for waiter in pending.waiters { waiter.resume(returning: Task.isCancelled) }
    }
    do {
      let installed = try await load(device)
      try Task.checkCancellation()
      if request === pending { bundleIDs = installed }
    } catch is CancellationError {
    } catch {
      if request === pending && !Task.isCancelled {
        self.error = error.localizedDescription
      }
    }
  }

  private final class Request {
    let device: SimulatorDevice
    var waiters: [CheckedContinuation<Bool, Never>] = []

    init(device: SimulatorDevice) { self.device = device }
  }
}
