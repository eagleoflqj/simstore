import SwiftUI

@MainActor
struct SimulatorPicker: View {
  let devices: [SimulatorDevice]
  let selectedDevice: SimulatorDevice?
  let selectDevice: (String) -> Void

  var body: some View {
    if let selectedDevice {
      Menu {
        Picker(
          "Simulator",
          selection: Binding(
            get: { selectedDevice.id },
            set: { selectDevice($0) })
        ) {
          ForEach(devices) { device in
            Text(verbatim: "\(device.name) · \(device.runtimeLabel) · \(device.id.suffix(8))")
              .tag(device.id)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      } label: {
        Label {
          Text(verbatim: selectedDevice.name)
            .lineLimit(1)
            .truncationMode(.tail)
        } icon: {
          Image(systemName: selectedDevice.symbolName)
        }
        .frame(maxWidth: 260, alignment: .leading)
      }
      .help(
        Text(
          verbatim: "\(selectedDevice.name) · \(selectedDevice.runtimeLabel)\n\(selectedDevice.id)")
      )
    } else {
      Label("No simulator selected", systemImage: "iphone")
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .fixedSize()
    }
  }
}

@MainActor
struct SimulatorDetailView: View {
  let device: SimulatorDevice
  let hasAppOperations: Bool
  let deviceManagerName: String?
  let start: () -> Void
  let shutdown: () -> Void
  let openDeviceManager: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      StableSizeView(device.formFactor, states: SimulatorDevice.FormFactor.allCases) { formFactor in
        Image(systemName: formFactor.symbolName)
      }
      .font(.system(size: 52, weight: .light))
      .foregroundStyle(Color.accentColor)
      .accessibilityHidden(true)

      VStack(spacing: 10) {
        Text(verbatim: device.name)
          .font(.system(size: 25, weight: .semibold))
          .multilineTextAlignment(.center)
          .lineLimit(2, reservesSpace: true)
          .help(Text(verbatim: device.name))
        HStack(spacing: 8) {
          Circle()
            .fill(device.state == "Booted" ? Color.green : Color.secondary)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
          Text(verbatim: device.stateLabel())
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
      }

      Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
        GridRow {
          Text("Runtime").foregroundStyle(.secondary)
          Text(verbatim: device.runtimeLabel)
        }
        GridRow(alignment: .top) {
          Text(verbatim: "UDID").foregroundStyle(.secondary)
          Text(verbatim: device.id)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
        }
      }
      .font(.system(size: 12))
      .padding(20)
      .frame(maxWidth: .infinity)
      .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

      HStack(spacing: 10) {
        if device.canStart || device.canShutdown || device.isTransitioning {
          SimulatorPowerButton(
            device: device, hasAppOperations: hasAppOperations, start: start, shutdown: shutdown)
        }
        DeviceManagerButton(name: deviceManagerName, action: openDeviceManager)
          .buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: 480)
    .padding(32)
  }
}

@MainActor
struct DeviceManagerButton: View {
  let name: String?
  let action: () -> Void

  var body: some View {
    Button(
      "Open \(name ?? "Xcode")",
      systemImage: name == nil ? "hammer" : "iphone.and.arrow.forward", action: action)
  }
}
