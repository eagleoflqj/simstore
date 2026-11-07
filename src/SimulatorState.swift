import Foundation

enum SimulatorState: String, Decodable, Sendable {
  case shutdown = "Shutdown"
  case booting = "Booting"
  case booted = "Booted"
  case shuttingDown = "Shutting Down"
  case unknown = "Unknown"

  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }

  // A boot request can wait for an existing boot to finish.
  // The power button stays disabled during that transition.
  var canStart: Bool { self == .shutdown || self == .booting }

  var canShutdown: Bool { self == .booted }

  var isTransitioning: Bool { self == .booting || self == .shuttingDown }

  var label: String {
    switch self {
    case .shutdown: String(localized: "Shutdown")
    case .booting: String(localized: "Booting")
    case .booted: String(localized: "Booted")
    case .shuttingDown: String(localized: "Shutting Down")
    case .unknown: String(localized: "Unknown State")
    }
  }

  var powerAction: PowerAction {
    switch self {
    case .shutdown, .unknown: .start
    case .booting: .starting
    case .booted: .shutdown
    case .shuttingDown: .shuttingDown
    }
  }

  var canPerformPowerAction: Bool {
    switch powerAction {
    case .start: canStart
    case .shutdown: canShutdown
    case .starting, .shuttingDown: false
    }
  }

  enum PowerAction: Hashable, Sendable {
    case start, starting, shutdown, shuttingDown

    var title: String {
      switch self {
      case .start: String(localized: "Start Simulator")
      case .starting: String(localized: "Starting…")
      case .shutdown: String(localized: "Shut Down")
      case .shuttingDown: String(localized: "Shutting Down…")
      }
    }

    var sizingStates: [Self] {
      switch self {
      case .start, .starting: [.start, .starting]
      case .shutdown, .shuttingDown: [.shutdown, .shuttingDown]
      }
    }
  }
}
