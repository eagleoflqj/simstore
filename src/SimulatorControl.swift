import Foundation

enum SimulatorControl {
  static func boot(
    _ deviceID: String,
    command: @escaping @Sendable (String, [String]) throws -> Data = SimulatorDiscovery
      .commandOutput
  ) async throws {
    try Task.checkCancellation()
    try await Task.detached(priority: .userInitiated) {
      _ = try command("/usr/bin/xcrun", ["simctl", "bootstatus", deviceID, "-b"])
    }.value
    try Task.checkCancellation()
  }
}
