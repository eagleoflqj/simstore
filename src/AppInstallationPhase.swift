import Foundation

enum AppInstallationPhase: Equatable, Sendable {
  case downloading(Int64)
  case verifying
  case extracting
  case installing
  case canceling
  case opening
  case uninstalling

  var canCancel: Bool {
    switch self {
    case .downloading, .verifying, .extracting: true
    case .installing, .canceling, .opening, .uninstalling: false
    }
  }

  var title: String {
    switch self {
    case .downloading: String(localized: "Downloading…")
    case .verifying: String(localized: "Verifying…")
    case .extracting: String(localized: "Preparing App…")
    case .installing: String(localized: "Installing…")
    case .canceling: String(localized: "Canceling…")
    case .opening: String(localized: "Opening…")
    case .uninstalling: String(localized: "Uninstalling…")
    }
  }

  func summary(totalBytes: Int64) -> String {
    if case .downloading(let bytes) = self {
      let fraction = Double(max(0, min(bytes, totalBytes))) / Double(max(1, totalBytes))
      return fraction.formatted(.percent.precision(.fractionLength(0)))
    }
    return title
  }
}
