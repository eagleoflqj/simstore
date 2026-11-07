import SwiftUI

struct SimulatorPowerButton: View {
  let device: SimulatorDevice
  let hasAppOperations: Bool
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
    case .shutdown: device.canShutdown && !hasAppOperations
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
    .help(helpText)
  }

  private var helpText: Text {
    if action == .shutdown && hasAppOperations {
      Text("Finish or cancel app operations before shutting down this simulator.")
    } else {
      Text(verbatim: action.title)
    }
  }
}
