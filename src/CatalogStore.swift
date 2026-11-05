import Foundation
import Observation

@MainActor
@Observable
final class CatalogStore {
  private(set) var catalog: AppCatalog?
  private(set) var isLoading = false
  private(set) var error: String?
  private(set) var isUsingCache = false

  @ObservationIgnored
  private let client: CatalogClient
  @ObservationIgnored
  private var hasLoadedCache = false
  @ObservationIgnored
  private var refreshWaiters: [CheckedContinuation<Bool, Never>] = []

  init(client: CatalogClient = .live) {
    self.client = client
  }

  func refresh() async {
    guard !Task.isCancelled else { return }
    guard !isLoading else {
      let ownerWasCancelled = await withCheckedContinuation { refreshWaiters.append($0) }
      if ownerWasCancelled && !Task.isCancelled { await refresh() }
      return
    }
    isLoading = true
    error = nil
    defer {
      isLoading = false
      let waiters = refreshWaiters
      refreshWaiters.removeAll()
      for waiter in waiters { waiter.resume(returning: Task.isCancelled) }
    }
    if !hasLoadedCache {
      hasLoadedCache = true
      if let cached = try? await client.loadCached() {
        catalog = cached
        isUsingCache = true
      }
    }
    do {
      try Task.checkCancellation()
      let fresh = try await client.fetch()
      try Task.checkCancellation()
      catalog = fresh
      isUsingCache = false
    } catch is CancellationError {
    } catch {
      guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
      self.error = error.localizedDescription
      isUsingCache = catalog != nil
    }
  }
}
