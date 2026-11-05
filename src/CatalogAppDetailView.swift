import SwiftUI

@MainActor
struct CatalogAppDetailView: View {
  let app: CatalogApp
  let device: SimulatorDevice
  let installedApps: InstalledAppsStore
  let installations: AppInstallationStore
  @State private var versionID: String
  @Environment(\.dismiss) private var dismiss

  init(
    app: CatalogApp, device: SimulatorDevice,
    installedApps: InstalledAppsStore, installations: AppInstallationStore
  ) {
    self.app = app
    self.device = device
    self.installedApps = installedApps
    self.installations = installations
    _versionID = State(initialValue: app.recommendedVersion(for: device.runtime).version)
  }

  private var runtime: String { device.runtime }

  private var version: CatalogVersion {
    app.versions.first(where: { $0.version == versionID }) ?? app.recommendedVersion(for: runtime)
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack(alignment: .top, spacing: 20) {
            CatalogIcon(app: app, size: 80)
            VStack(alignment: .leading, spacing: 8) {
              Text(verbatim: app.name).font(.system(size: 26, weight: .bold))
              Text(verbatim: app.categoryTitle).font(.system(size: 12)).foregroundStyle(.secondary)
              Text(verbatim: app.displayDescription).font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
            GridRow {
              Text("Simulator").foregroundStyle(.secondary)
              Text(verbatim: "\(device.name) · \(device.runtimeLabel)")
            }
            GridRow {
              Text("Version").foregroundStyle(.secondary)
              Picker(selection: $versionID) {
                ForEach(app.versions) { build in
                  Text(verbatim: build.version).tag(build.version)
                }
              } label: {
                Text("Available Versions")
              }
              .labelsHidden()
              .accessibilityIdentifier("catalog-version")
              .disabled(installations.phase(appID: app.id, deviceID: device.id) != nil)
              .frame(maxWidth: 240)
            }
            GridRow {
              Text("Requires").foregroundStyle(.secondary)
              Text(verbatim: version.minimumOSLabel)
            }
            GridRow {
              Text("Download Size").foregroundStyle(.secondary)
              Text(
                verbatim: ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file))
            }
            GridRow {
              Text("Published").foregroundStyle(.secondary)
              Text(
                Date(timeIntervalSince1970: TimeInterval(version.time)),
                format: .dateTime.year().month().day())
            }
            GridRow {
              Text("License").foregroundStyle(.secondary)
              Text(verbatim: app.license).textSelection(.enabled)
            }
            GridRow {
              Text("Bundle ID").foregroundStyle(.secondary)
              Text(verbatim: app.bundleID).font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
            }
          }
          .font(.system(size: 13))
          .frame(maxWidth: .infinity, alignment: .leading)

          if !version.isCompatible(with: runtime) {
            Label {
              Text(
                "This build requires iOS \(version.minSimulatorOS) or later. It may not work on iOS \(runtime)."
              )
            } icon: {
              Image(systemName: "exclamationmark.triangle")
            }
            .font(.system(size: 12))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
          }

          AppInstallStatusView(
            appID: app.id, deviceID: device.id, version: version, store: installations)

          HStack(spacing: 20) {
            Link(destination: app.repository) {
              Label("Source Repository", systemImage: "curlybraces")
            }
            Link(destination: AppConfiguration.releaseURL(appID: app.id, version: version.version))
            {
              Label("Build Release", systemImage: "arrow.up.right.square")
            }
          }

          DisclosureGroup("Build Details") {
            VStack(alignment: .leading, spacing: 12) {
              buildDetail(
                "Source Revision", value: version.revision,
                link: AppConfiguration.commitURL(
                  repository: app.repository, revision: version.revision))
              buildDetail(
                "Recipe Revision", value: version.recipeRevision,
                link: AppConfiguration.commitURL(
                  repository: AppConfiguration.buildsRepositoryURL, revision: version.recipeRevision
                ))
              buildDetail("SHA-256", value: version.sha256)
            }
            .padding(.top, 12)
          }
          .disclosureGroupStyle(DetailsDisclosureStyle())
          .font(.system(size: 12))

          Text(
            "License refers to the upstream project’s main license. Some components or resources may use other licenses."
          )
          .font(.system(size: 11)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
      }
      Divider()
      HStack {
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        AppInstallButton(
          app: app, version: version, device: device, store: installations,
          isInstalled: installedApps.isInstalled(bundleID: app.bundleID, deviceID: device.id),
          allowsIncompatible: true
        )
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("detail-install")
      }
      .padding(20)
    }
    .frame(width: 580, height: 560)
  }

  private func buildDetail(_ title: LocalizedStringKey, value: String, link: URL? = nil)
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).foregroundStyle(.secondary)
      Group {
        if let link {
          Link(destination: link) { Text(verbatim: value) }
        } else {
          Text(verbatim: value).textSelection(.enabled)
        }
      }
      .font(.system(size: 10, design: .monospaced))
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct DetailsDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation { configuration.isExpanded.toggle() }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
            .accessibilityHidden(true)
          configuration.label
          Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if configuration.isExpanded {
        configuration.content.padding(.leading, 16)
      }
    }
  }
}
