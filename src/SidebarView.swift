import AppKit
import SwiftUI

@MainActor
struct SidebarView: View {
  let discovery: SimulatorDiscovery?
  let isChecking: Bool
  let needsXcode: Bool
  let selectedDeviceID: String?
  let startingDeviceIDs: Set<String>
  let selectDevice: (String) -> Void
  let openRepository: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 37, height: 37)
        Text(verbatim: "SimStore")
          .font(.system(size: 22, weight: .bold))
          .tracking(-0.7)
      }
      .padding(.horizontal, 20)
      .padding(.top, 24)
      .padding(.bottom, 27)
      .fixedSize(horizontal: false, vertical: true)

      VStack(spacing: 5) {
        Label("Discover", systemImage: "safari")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.accentColor)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 11)
          .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
          .accessibilityAddTraits(.isSelected)
        sidebarPlaceholder("Installed", systemImage: "square.grid.2x2")
        sidebarPlaceholder("Updates", systemImage: "arrow.triangle.2.circlepath")
      }
      .padding(.horizontal, 12)
      .fixedSize(horizontal: false, vertical: true)

      simulatorListTitle
        .textCase(.uppercase)
        .font(.system(size: 10, weight: .semibold))
        .tracking(1)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 15)
        .fixedSize(horizontal: false, vertical: true)

      if let discovery, !discovery.devices.isEmpty {
        List(
          selection: Binding(
            get: { selectedDeviceID },
            set: { if let id = $0 { selectDevice(id) } })
        ) {
          ForEach(discovery.devices) { device in
            Label {
              VStack(alignment: .leading, spacing: 4) {
                Text(device.name).font(.system(size: 12, weight: .medium))
                Text(
                  "\(device.runtimeLabel) · \(device.stateLabel(isStarting: startingDeviceIDs.contains(device.id)))"
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
              }
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
              Image(systemName: device.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            }
            .tag(device.id)
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .accessibilityElement(children: .combine)
            .help(Text(verbatim: device.id))
          }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .accessibilityLabel(simulatorListTitle)
        .frame(minHeight: 0)
      } else {
        VStack(alignment: .leading, spacing: 7) {
          Text(
            isChecking
              ? String(localized: "Checking for devices…")
              : needsXcode
                ? String(localized: "Xcode required")
                : discovery == nil
                  ? String(localized: "No devices to display")
                  : String(localized: "No simulators yet")
          )
          .font(.system(size: 12, weight: .medium))
          Text(
            needsXcode
              ? String(localized: "Install Xcode to add iPhone and iPad simulators.")
              : String(localized: "Your iPhone and iPad simulators will appear here.")
          )
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
      }

      Spacer(minLength: 24)

      Button(action: openRepository) {
        Label("App Repository", systemImage: "arrow.up.right.square")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .padding(24)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var simulatorListTitle: Text { Text("Simulators") }

  private func sidebarPlaceholder(_ title: LocalizedStringKey, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .font(.system(size: 13))
      .foregroundStyle(.tertiary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
  }
}
