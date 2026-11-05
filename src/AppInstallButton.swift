import SwiftUI

struct AppInstallButton: View {
  let app: CatalogApp
  let version: CatalogVersion
  let device: SimulatorDevice
  let store: AppInstallationStore
  let isInstalled: Bool?
  var allowsIncompatible = false
  var isDefaultAction = false

  private enum Action: CaseIterable {
    case install, open, cancel, installing, canceling, opening

    var title: String {
      switch self {
      case .install: String(localized: "Install")
      case .open: String(localized: "Open")
      case .cancel: String(localized: "Cancel")
      case .installing: AppInstallationPhase.installing.title
      case .canceling: AppInstallationPhase.canceling.title
      case .opening: AppInstallationPhase.opening.title
      }
    }
  }

  private var phase: AppInstallationPhase? {
    store.phase(appID: app.id, deviceID: device.id)
  }

  private var action: Action {
    switch phase {
    case .downloading, .verifying, .extracting: .cancel
    case .installing: .installing
    case .canceling: .canceling
    case .opening: .opening
    case nil: isInstalled == true ? .open : .install
    }
  }

  private var enabled: Bool {
    if let phase { return phase.canCancel }
    guard device.state == "Booted", let isInstalled else { return false }
    return isInstalled || allowsIncompatible || version.isCompatible(with: device.runtime)
  }

  var body: some View {
    if phase == nil {
      button.buttonStyle(.borderedProminent)
    } else {
      button.buttonStyle(.bordered)
    }
  }

  private var button: some View {
    Button {
      switch action {
      case .install: store.install(app: app, version: version, on: device)
      case .open: store.open(app: app, on: device)
      case .cancel: store.cancel(appID: app.id, deviceID: device.id)
      case .installing, .canceling, .opening: break
      }
    } label: {
      StableSizeView(action, states: Action.allCases) { value in
        Text(verbatim: value.title)
      }
      .lineLimit(1)
    }
    .disabled(!enabled)
    .keyboardShortcut(isDefaultAction && phase == nil ? .defaultAction : nil)
    .accessibilityLabel(Text(verbatim: "\(action.title) \(app.name)"))
    .accessibilityValue(Text(verbatim: phase?.summary(totalBytes: version.size) ?? ""))
    .help(Text(verbatim: version.minimumOSLabel))
  }
}

struct AppInstallStatusView: View {
  let appID: String
  let deviceID: String
  let version: CatalogVersion
  let store: AppInstallationStore

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let phase = store.phase(appID: appID, deviceID: deviceID) {
        if case .downloading(let bytes) = phase {
          DownloadProgressView(receivedBytes: bytes, totalBytes: version.size, title: phase.title)
        } else {
          HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(verbatim: phase.title)
          }
        }
      }
      if let error = store.error(appID: appID, deviceID: deviceID) {
        Label {
          Text(verbatim: error).textSelection(.enabled)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("installation-error")
      }
    }
    .font(.system(size: 12))
  }
}
