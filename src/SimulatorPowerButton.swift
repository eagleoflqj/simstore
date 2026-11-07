import SwiftUI

struct SimulatorPowerButton: View {
  let device: SimulatorDevice
  let start: () -> Void
  let shutdown: () -> Void

  private enum Action: Hashable {
    case start, starting, shutdown, shuttingDown

    var title: String {
      switch self {
      case .start: String(localized: "Start Simulator")
      case .starting: String(localized: "Starting…")
      case .shutdown: String(localized: "Shut Down")
      case .shuttingDown: String(localized: "Shutting Down…")
      }
    }
  }

  private var action: Action {
    switch device.state {
    case "Booted": .shutdown
    case "Booting": .starting
    case "Shutting Down": .shuttingDown
    default: .start
    }
  }

  private var states: [Action] {
    switch action {
    case .start, .starting: [.start, .starting]
    case .shutdown, .shuttingDown: [.shutdown, .shuttingDown]
    }
  }

  private var enabled: Bool {
    switch action {
    case .start: device.canStart
    case .shutdown: device.canShutdown
    case .starting, .shuttingDown: false
    }
  }

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
        StableSizeView(action, states: states) { value in
          Text(verbatim: value.title)
        }
      } icon: {
        Image(systemName: "power")
      }
    }
    .disabled(!enabled)
    .accessibilityLabel(Text(verbatim: "\(action.title) \(device.name)"))
    .help(Text(verbatim: action.title))
  }
}
