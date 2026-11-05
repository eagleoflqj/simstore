import SwiftUI

struct CatalogAppCard: View {
  let app: CatalogApp
  let device: SimulatorDevice
  let installedApps: InstalledAppsStore
  let installations: AppInstallationStore
  @FocusState.Binding var focusedAppID: String?
  let showDetails: () -> Void

  private var runtime: String { device.runtime }

  var body: some View {
    let version = app.recommendedVersion(for: runtime)
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 12) {
          CatalogIcon(app: app)
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: app.name)
              .font(.system(size: 15, weight: .semibold))
              .lineLimit(2, reservesSpace: true)
            Text(verbatim: app.categoryTitle)
              .font(.system(size: 10)).foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
        }
        Text(verbatim: app.displayDescription)
          .font(.system(size: 12)).foregroundStyle(.secondary)
          .lineLimit(2, reservesSpace: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      HStack {
        HStack(spacing: 4) {
          if let phase = installations.phase(appID: app.id, deviceID: device.id) {
            Text(verbatim: phase.summary(totalBytes: version.size)).foregroundStyle(.secondary)
              .monospacedDigit()
          } else if installations.error(appID: app.id, deviceID: device.id) != nil {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            Text(verbatim: version.version).monospacedDigit()
          } else if !version.isCompatible(with: runtime) {
            Label("iOS \(version.minSimulatorOS)+", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          } else {
            Text(verbatim: version.version).monospacedDigit()
          }
        }
        .lineLimit(1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        Spacer(minLength: 4)
        Text(verbatim: ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        AppInstallButton(
          app: app, version: version, device: device, store: installations,
          isInstalled: installedApps.isInstalled(bundleID: app.bundleID, deviceID: device.id)
        )
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("catalog-install-\(app.id)")
      }
      .font(.system(size: 11))
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      Button(action: showDetails) {
        RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor))
          .contentShape(RoundedRectangle(cornerRadius: 14))
      }
      .buttonStyle(.plain)
      .focused($focusedAppID, equals: app.id)
      .accessibilityLabel(Text(verbatim: app.name))
      .accessibilityValue(
        Text(
          verbatim:
            "\(app.displayDescription) · \(version.version) · \(version.minimumOSLabel) · \(ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file))"
        )
      )
      .accessibilityHint(Text("View app details and versions"))
      .accessibilityIdentifier("catalog-app-\(app.id)")
      .accessibilitySortPriority(1)
      .help(
        Text(
          verbatim: installations.error(appID: app.id, deviceID: device.id)
            ?? app.displayDescription))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07))
    }
    .contentShape(RoundedRectangle(cornerRadius: 14))
  }
}
