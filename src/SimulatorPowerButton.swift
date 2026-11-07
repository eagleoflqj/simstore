import SwiftUI

struct SimulatorPowerButton: View {
  let device: SimulatorDevice
  let start: () -> Void
  let shutdown: () -> Void

  private var action: SimulatorState.PowerAction { device.state.powerAction }

  var body: some View {
    Group {
      if action == .start {
        button.buttonStyle(.borderedProminent)
      } else {
        button.buttonStyle(.bordered)
      }
    }
    .accessibilityIdentifier("simulator-power")
  }

  private var button: some View {
    Button(action: action == .shutdown ? shutdown : start) {
      Label {
        StableSizeView(action, states: action.sizingStates) { value in
          Text(verbatim: value.title)
        }
      } icon: {
        Image(systemName: "power")
      }
    }
    .disabled(!device.state.canPerformPowerAction)
    .accessibilityLabel(Text(verbatim: "\(action.title) \(device.name)"))
    .help(Text(verbatim: action.title))
  }
}
