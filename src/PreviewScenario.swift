#if DEBUG
  import Foundation

  enum PreviewScenario: String, Sendable {
    case noXcode = "no-xcode"
    case noSimulators = "no-simulators"

    static func parse(_ arguments: [String]) throws -> Self? {
      guard let index = arguments.firstIndex(of: "--preview") else { return nil }
      guard arguments.indices.contains(index + 1),
        let scenario = Self(rawValue: arguments[index + 1])
      else {
        throw NSError(
          domain: "PreviewScenario", code: 1,
          userInfo: [
            NSLocalizedDescriptionKey: "Use --preview no-xcode or --preview no-simulators."
          ])
      }
      return scenario
    }

    func discover(
      installedXcodeURL: URL?,
      command: @escaping Command.Runner = Command.run
    ) async throws -> SimulatorDiscovery {
      switch self {
      case .noXcode:
        throw SimulatorDiscoveryError.xcodeNotInstalled
      case .noSimulators:
        return try await SimulatorDiscovery.scan(installedXcodeURL: installedXcodeURL) {
          executable, arguments in
          if executable == Command.xcrunExecutable,
            arguments.starts(with: [Command.simctlTool, "list", "devices"])
          {
            return Data(#"{"devices": {}}"#.utf8)
          }
          return try command(executable, arguments)
        }
      }
    }
  }
#endif
