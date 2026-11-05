import Foundation

enum SimulatorApplications {
  static func install(
    _ bundle: URL, on device: SimulatorDevice,
    command: @escaping Command.Runner = Command.run
  ) async throws {
    guard device.state == "Booted" else { throw SimulatorApplicationsError.notRunning }
    try Task.checkCancellation()
    try await Task.detached(priority: .userInitiated) {
      _ = try Command.simctl(["install", device.id, bundle.path], using: command)
    }.value
  }

  static func launch(
    _ bundleID: String, on device: SimulatorDevice,
    command: @escaping Command.Runner = Command.run
  ) async throws {
    guard device.state == "Booted" else { throw SimulatorApplicationsError.notRunning }
    try Task.checkCancellation()
    try await Task.detached(priority: .userInitiated) {
      _ = try Command.simctl(["launch", device.id, bundleID], using: command)
    }.value
  }

  static func installedBundleIDs(
    on device: SimulatorDevice,
    command: @escaping Command.Runner = Command.run
  ) async throws -> Set<String> {
    guard device.state == "Booted" else { throw SimulatorApplicationsError.notRunning }
    try Task.checkCancellation()
    let identifiers = try await Task.detached(priority: .userInitiated) {
      let data = try Command.simctl(["listapps", device.id], using: command)
      return try decodeBundleIDs(data)
    }.value
    try Task.checkCancellation()
    return identifiers
  }

  static func decodeBundleIDs(_ data: Data) throws -> Set<String> {
    guard
      let applications = try PropertyListSerialization.propertyList(
        from: data, format: nil) as? [String: [String: Any]],
      applications.keys.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    else { throw SimulatorApplicationsError.invalidResponse }
    return Set(applications.keys)
  }
}

enum SimulatorApplicationsError: LocalizedError {
  case notRunning
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .notRunning:
      String(
        localized:
          "Start the simulator. SimStore will automatically show apps that aren’t installed.")
    case .invalidResponse:
      String(localized: "The simulator returned an invalid app list.")
    }
  }
}
