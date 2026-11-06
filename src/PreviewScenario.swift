#if DEBUG
  import Foundation

  enum PreviewScenario: String, CaseIterable, Sendable {
    case noXcode = "no-xcode"
    case noSimulators = "no-simulators"
    case incompatible

    static func parse(_ arguments: [String]) throws -> Self? {
      guard let index = arguments.firstIndex(of: "--preview") else { return nil }
      guard arguments.indices.contains(index + 1),
        let scenario = Self(rawValue: arguments[index + 1])
      else {
        throw NSError(
          domain: "PreviewScenario", code: 1,
          userInfo: [
            NSLocalizedDescriptionKey:
              "Use --preview with one of: \(Self.allCases.map(\.rawValue).joined(separator: ", "))."
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
      case .noSimulators, .incompatible:
        return try await SimulatorDiscovery.scan(installedXcodeURL: installedXcodeURL) {
          executable, arguments in
          if executable == Command.xcrunExecutable,
            arguments.starts(with: [Command.simctlTool, "list", "devices"])
          {
            if self == .incompatible {
              return Data(
                #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-12-0":[{"udid":"00000000-0000-0000-0000-000000000001","name":"iPhone 8","state":"Booted","isAvailable":true}]}}"#
                  .utf8)
            }
            return Data(#"{"devices": {}}"#.utf8)
          }
          return try command(executable, arguments)
        }
      }
    }

    static func rejectDeviceAction() throws -> Never {
      throw CocoaError(.featureUnsupported)
    }
  }
#endif
