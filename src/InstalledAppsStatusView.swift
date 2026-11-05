import SwiftUI

@MainActor
struct InstalledAppsStatusView: View {
  let device: SimulatorDevice
  let store: InstalledAppsStore
  let refresh: () -> Void

  var body: some View {
    Group {
      if device.state != "Booted" {
        ContentUnavailableView {
          Label("Simulator Not Running", systemImage: "power")
        } description: {
          Text(verbatim: SimulatorApplicationsError.notRunning.localizedDescription)
        }
      } else if store.isLoading || store.deviceID != device.id {
        VStack(spacing: 14) {
          ProgressView()
          Text("Checking Installed Apps…").foregroundStyle(.secondary)
        }
      } else {
        ContentUnavailableView {
          Label("Couldn’t Read Installed Apps", systemImage: "exclamationmark.triangle")
        } description: {
          Text(
            verbatim: store.error
              ?? String(localized: "Try again to load the app list."))
        } actions: {
          Button("Try Again", action: refresh)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
