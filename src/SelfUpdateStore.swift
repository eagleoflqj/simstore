import Foundation
import Observation

@MainActor
@Observable
final class SelfUpdateStore {
  let current: SelfUpdateBuild?
  let os: String
  private(set) var release: SelfUpdateRelease?
  private(set) var isChecking = false
  private(set) var hasChecked = false
  private(set) var phase: AppInstallationPhase?
  private(set) var error: String?

  @ObservationIgnored private let client: SelfUpdateClient
  @ObservationIgnored private let updater: SelfUpdater
  @ObservationIgnored private let restart: @MainActor (PreparedSelfUpdate) async throws -> Void
  @ObservationIgnored private var job: Task<Void, Never>?
  @ObservationIgnored private var requestID: UUID?

  var isBusy: Bool { isChecking || phase != nil }

  init(
    current: SelfUpdateBuild? = try? SelfUpdateBuild.read(at: Bundle.main.bundleURL),
    os: String = SelfUpdatePackage.currentOS, client: SelfUpdateClient = SelfUpdateClient(),
    updater: SelfUpdater = SelfUpdater(),
    restart: @escaping @MainActor (PreparedSelfUpdate) async throws -> Void = SelfUpdater.restart
  ) {
    self.current = current
    self.os = os
    self.client = client
    self.updater = updater
    self.restart = restart
  }

  func check() {
    guard !isBusy else { return }
    error = nil
    release = nil
    guard let current else {
      error = SelfUpdateError.invalidVersion.localizedDescription
      return
    }
    isChecking = true
    job = Task { [self] in
      defer {
        isChecking = false
        job = nil
      }
      do {
        let index = try await client.fetch()
        release = index.recommendedUpdate(from: current, os: os)
        hasChecked = true
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  func install() {
    guard !isBusy, let release, let current else { return }
    let id = UUID()
    requestID = id
    error = nil
    phase = .downloading(0)
    job = Task { [self] in
      defer {
        phase = nil
        job = nil
        requestID = nil
      }
      do {
        if release.isNightly {
          let index = try await client.fetch()
          guard index.recommendedUpdate(from: current, os: os) == release else {
            throw SelfUpdateError.releaseChanged
          }
        }
        let prepared = try await updater.prepare(release) { [weak self] value in
          guard let self, requestID == id, phase != .canceling else { return }
          if case .downloading(let bytes) = value, case .downloading(let previous) = phase {
            phase = .downloading(max(bytes, previous))
          } else if case .downloading = value {
            return
          } else {
            phase = value
          }
        }
        defer { prepared.remove() }
        try Task.checkCancellation()
        phase = .installing
        try await restart(prepared)
      } catch is CancellationError {
      } catch {
        if !Task.isCancelled {
          self.error = error.localizedDescription
          self.release = nil
          hasChecked = false
        }
      }
    }
  }

  func cancel() {
    guard phase?.canCancel == true else { return }
    phase = .canceling
    job?.cancel()
  }

  func consumeFailureReport() -> Bool {
    guard !isBusy, let message = SelfUpdateInstallation.consumeFailure(at: updater.reportURL) else {
      return false
    }
    error = message
    return true
  }
}
