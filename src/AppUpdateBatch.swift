import Foundation

struct AppUpdateBatch {
  struct Item: Identifiable {
    let app: CatalogApp
    let version: CatalogVersion
    var id: String { app.id }
  }

  enum Outcome {
    case updated
    case failed(String)
    case canceled
  }

  let id = UUID()
  let items: [Item]
  var outcomes: [String: Outcome] = [:]
  var currentAppID: String?
  var isRunning = true
  var isStopping = false

  var total: Int { items.count }
  var completed: Int { outcomes.count }
  var updated: Int {
    outcomes.values.filter { if case .updated = $0 { true } else { false } }.count
  }
  var failed: Int { outcomes.values.filter { if case .failed = $0 { true } else { false } }.count }
  var canceled: Int {
    outcomes.values.filter { if case .canceled = $0 { true } else { false } }.count
  }

  var currentApp: CatalogApp? { items.first { $0.id == currentAppID }?.app }

  var failures: [(app: CatalogApp, message: String)] {
    items.compactMap { item in
      guard case .failed(let message) = outcomes[item.id] else { return nil }
      return (item.app, message)
    }
  }
}
