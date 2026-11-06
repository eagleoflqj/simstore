import AppKit
import SwiftUI

@MainActor
struct SidebarView: View {
  let discovery: SimulatorDiscovery?
  let isChecking: Bool
  let needsXcode: Bool
  @Binding var section: LibrarySection
  let updateCount: Int?
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
        ForEach(LibrarySection.allCases, id: \.self) { item in
          Button {
            section = item
          } label: {
            HStack(spacing: 8) {
              Label {
                Text(verbatim: item.title)
              } icon: {
                Image(systemName: item.symbolName)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              if item == .updates, let count = visibleUpdateCount {
                Text(count, format: .number)
                  .font(.system(size: 10, weight: .semibold))
                  .monospacedDigit()
                  .foregroundStyle(.white)
                  .padding(.horizontal, 6)
                  .frame(height: 18)
                  .background(Color.accentColor, in: Capsule())
                  .accessibilityHidden(true)
              }
            }
            .frame(minHeight: 18)
            .font(.system(size: 13, weight: section == item ? .semibold : .regular))
            .foregroundStyle(section == item ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
              section == item ? Color.accentColor.opacity(0.10) : Color.clear,
              in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(verbatim: item.title))
          .accessibilityValue(
            Text(verbatim: item == .updates ? visibleUpdateCount?.formatted() ?? "" : "")
          )
          .accessibilityAddTraits(section == item ? .isSelected : [])
          .accessibilityIdentifier("library-\(item.rawValue)")
        }
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

  private var visibleUpdateCount: Int? {
    guard let updateCount, updateCount > 0 else { return nil }
    return updateCount
  }
}
