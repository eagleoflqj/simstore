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
}
