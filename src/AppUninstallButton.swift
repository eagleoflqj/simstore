import SwiftUI

struct AppUninstallButton: View {
  let app: CatalogApp
  let device: SimulatorDevice
  let installedApps: InstalledAppsStore
  let installations: AppInstallationStore

  @State private var showsConfirmation = false
  @State private var target: Target?

  private struct Target {
    let app: CatalogApp
    let device: SimulatorDevice
  }

  private var title: Text { Text("Uninstall") }

  var body: some View {
    Button(role: .destructive) {
      target = Target(app: app, device: device)
      showsConfirmation = true
    } label: {
      Label {
        title
      } icon: {
        Image(systemName: "trash")
      }
    }
    .buttonStyle(.bordered)
    .disabled(
      device.state != .booted
        || installedApps.application(bundleID: app.bundleID, deviceID: device.id)?.isUserApplication
          != true
        || installations.phase(appID: app.id, deviceID: device.id) != nil
    )
    .accessibilityLabel(Text("Uninstall \(app.name)"))
    .alert("Uninstall \(app.name)?", isPresented: $showsConfirmation, presenting: target) {
      target in
      Button("Cancel", role: .cancel) {}
      Button(role: .destructive) {
        installations.uninstall(app: target.app, on: target.device)
      } label: {
        title
      }
    } message: { target in
      Text("\(target.app.name) and its data will be removed from \(target.device.name).")
    }
  }
}
