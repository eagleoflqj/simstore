import Foundation

enum SimulatorControl {
  static func boot(
    _ deviceID: String,
    command: @escaping Command.Runner = Command.run
  ) async throws {
    try Task.checkCancellation()
    try await Task.detached(priority: .userInitiated) {
      _ = try Command.simctl(["bootstatus", deviceID, "-b"], using: command)
    }.value
    try Task.checkCancellation()
  }

  static func shutdown(
    _ deviceID: String,
    command: @escaping Command.Runner = Command.run
  ) async throws {
    try Task.checkCancellation()
    try await Task.detached(priority: .userInitiated) {
      _ = try Command.simctl(["shutdown", deviceID], using: command)
    }.value
    try Task.checkCancellation()
  }
}
