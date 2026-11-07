import Foundation

extension SimulatorDevice {
  enum FormFactor: CaseIterable, Hashable {
    case phone
    case tablet

    var symbolName: String {
      switch self {
      case .phone: "iphone"
      case .tablet: "ipad.landscape"
      }
    }
  }

  var formFactor: FormFactor { name.contains("iPad") ? .tablet : .phone }

  var symbolName: String { formFactor.symbolName }

  var runtimeLabel: String { String(localized: "iOS \(runtime)") }

  func stateLabel() -> String {
    switch state {
    case "Booted": String(localized: "Booted")
    case "Shutdown": String(localized: "Shutdown")
    case "Booting": String(localized: "Booting")
    case "Shutting Down": String(localized: "Shutting Down")
    default: state
    }
  }
}
