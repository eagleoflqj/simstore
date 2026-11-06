import Foundation

enum AppInstallationAction: CaseIterable {
  case install, open, update, downgrade, replace
  case cancel, installing, canceling, opening, uninstalling

  var title: String {
    switch self {
    case .install: String(localized: "Install")
    case .open: String(localized: "Open")
    case .update: String(localized: "Update")
    case .downgrade: String(localized: "Downgrade")
    case .replace: Self.install.title
    case .cancel: String(localized: "Cancel")
    case .installing: AppInstallationPhase.installing.title
    case .canceling: AppInstallationPhase.canceling.title
    case .opening: AppInstallationPhase.opening.title
    case .uninstalling: AppInstallationPhase.uninstalling.title
    }
  }

  var isVersionChange: Bool {
    self == .update || self == .downgrade || self == .replace
  }

  var needsConfirmation: Bool { self == .downgrade || self == .replace }

  static func forVersion(
    _ version: CatalogVersion, installed: SimulatorApplication?, allowsChanges: Bool
  ) -> Self {
    guard let installed else { return .install }
    guard allowsChanges, installed.isUserApplication else { return .open }
    switch version.comparison(with: installed.version) {
    case .orderedSame: return .open
    case .orderedDescending: return .update
    case .orderedAscending: return .downgrade
    case nil: return .replace
    }
  }
}
