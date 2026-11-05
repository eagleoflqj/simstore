import Foundation
import Observation

@MainActor
@Observable
final class AppInstallationStore {
  struct Key: Hashable {
    let appID: String
    let deviceID: String
  }

  private var phases: [Key: AppInstallationPhase] = [:]
  private var errors: [Key: String] = [:]
  private(set) var openedApp: Key?
  @ObservationIgnored private let installer: AppInstaller
  @ObservationIgnored private let didInstall: @MainActor (String, String) -> Void
  @ObservationIgnored private let showDevice: @MainActor (SimulatorDevice) async throws -> Void
  @ObservationIgnored private let didOpen: @MainActor (String, String) -> Void
  @ObservationIgnored private var jobs: [Key: Task<Void, Never>] = [:]
  @ObservationIgnored private var requests: [Key: UUID] = [:]

  init(
    installer: AppInstaller = AppInstaller(),
    showDevice: @escaping @MainActor (SimulatorDevice) async throws -> Void,
    didInstall: @escaping @MainActor (String, String) -> Void = { _, _ in },
    didOpen: @escaping @MainActor (String, String) -> Void = { _, _ in }
  ) {
    self.installer = installer
    self.didInstall = didInstall
    self.showDevice = showDevice
    self.didOpen = didOpen
  }

  func phase(appID: String, deviceID: String) -> AppInstallationPhase? {
    phases[Key(appID: appID, deviceID: deviceID)]
  }

  func error(appID: String, deviceID: String) -> String? {
    errors[Key(appID: appID, deviceID: deviceID)]
  }

  func install(app: CatalogApp, version: CatalogVersion, on device: SimulatorDevice) {
    let key = Key(appID: app.id, deviceID: device.id)
    guard jobs[key] == nil else { return }
    let request = UUID()
    requests[key] = request
    errors[key] = nil
    phases[key] = .downloading(0)
    jobs[key] = Task { [self] in
      defer { finish(key) }
      do {
        try await installer.install(app: app, version: version, on: device) { [weak self] phase in
          guard let self, requests[key] == request, phases[key] != .canceling else { return }
          if case .downloading(let bytes) = phase, case .downloading(let previous) = phases[key] {
            phases[key] = .downloading(max(bytes, previous))
          } else if case .downloading = phase {
            return
          } else {
            phases[key] = phase
          }
        }
        didInstall(app.bundleID, device.id)
      } catch is CancellationError {
      } catch {
        if !Task.isCancelled { errors[key] = error.localizedDescription }
      }
    }
  }

  func cancel(appID: String, deviceID: String) {
    let key = Key(appID: appID, deviceID: deviceID)
    guard phases[key]?.canCancel == true else { return }
    phases[key] = .canceling
    jobs[key]?.cancel()
  }

  func open(app: CatalogApp, on device: SimulatorDevice) {
    let key = Key(appID: app.id, deviceID: device.id)
    guard jobs[key] == nil else { return }
    openedApp = nil
    errors[key] = nil
    phases[key] = .opening
    jobs[key] = Task {
      defer { finish(key) }
      do {
        try await installer.open(app: app, on: device)
        try await showDevice(device)
        didOpen(app.bundleID, device.id)
        openedApp = key
      } catch {
        errors[key] = error.localizedDescription
      }
    }
  }

  private func finish(_ key: Key) {
    jobs[key] = nil
    requests[key] = nil
    phases[key] = nil
  }
}
