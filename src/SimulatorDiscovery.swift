import Foundation

enum SimulatorDiscoveryError: LocalizedError, Equatable {
  case xcodeNotInstalled

  var errorDescription: String? { String(localized: "Xcode is not installed.") }
}

struct SimulatorDevice: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let runtime: String
  let state: String

  var canStart: Bool { state == "Shutdown" || state == "Booting" }

  var isTransitioning: Bool { state == "Booting" || state == "Shutting Down" }
}

struct SimulatorDiscovery: Sendable {
  let developerDirectory: URL
  let devices: [SimulatorDevice]

  var deviceManager: (name: String, url: URL)? {
    let applications = [
      (
        name: "Device Hub",
        url: xcodeURL.appendingPathComponent("Contents/Applications/DeviceHub.app")
      ),
      (
        name: "Simulator",
        url: developerDirectory.appendingPathComponent("Applications/Simulator.app")
      ),
    ]
    return applications.first { FileManager.default.fileExists(atPath: $0.url.path) }
  }

  var xcodeURL: URL {
    developerDirectory.deletingLastPathComponent().deletingLastPathComponent()
  }

  static func scan(
    installedXcodeURL: URL?,
    command: @escaping @Sendable (String, [String]) throws -> Data = commandOutput
  ) async throws -> SimulatorDiscovery {
    try await Task.detached(priority: .userInitiated) {
      let directoryData: Data
      do {
        directoryData = try command("/usr/bin/xcode-select", ["--print-path"])
      } catch {
        if isXcodeApplication(installedXcodeURL) { throw error }
        throw SimulatorDiscoveryError.xcodeNotInstalled
      }
      let directory = String(decoding: directoryData, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard directory.hasPrefix("/") else {
        throw NSError(
          domain: "SimulatorDiscovery", code: 1,
          userInfo: [
            NSLocalizedDescriptionKey: String(
              localized: "Xcode did not provide a valid developer directory.")
          ])
      }
      let developerDirectory = URL(fileURLWithPath: directory)
      let selectedXcode = developerDirectory.deletingLastPathComponent().deletingLastPathComponent()
      guard isXcodeApplication(selectedXcode) || isXcodeApplication(installedXcodeURL) else {
        throw SimulatorDiscoveryError.xcodeNotInstalled
      }
      let deviceData = try command(
        "/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"])
      return SimulatorDiscovery(
        developerDirectory: developerDirectory, devices: try decodeDevices(deviceData))
    }.value
  }

  private static func isXcodeApplication(_ url: URL?) -> Bool {
    guard let url, FileManager.default.fileExists(atPath: url.path) else { return false }
    return Bundle(url: url)?.bundleIdentifier == "com.apple.dt.Xcode"
  }

  static func decodeDevices(_ data: Data) throws -> [SimulatorDevice] {
    struct Response: Decodable {
      struct Device: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool
      }
      let devices: [String: [Device]]
    }

    let response = try JSONDecoder().decode(Response.self, from: data)
    let prefix = "com.apple.CoreSimulator.SimRuntime.iOS-"
    return response.devices.filter { $0.key.hasPrefix(prefix) }.flatMap { runtime, devices in
      devices.filter(\.isAvailable).map { device in
        SimulatorDevice(
          id: device.udid,
          name: device.name,
          runtime: String(runtime.dropFirst(prefix.count)).replacingOccurrences(of: "-", with: "."),
          state: device.state
        )
      }
    }.sorted {
      if $0.name == $1.name { return $0.id < $1.id }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  static func commandOutput(_ executable: String, arguments: [String]) throws -> Data {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      let diagnostic = String(decoding: data, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      throw NSError(
        domain: "SimulatorDiscovery", code: Int(process.terminationStatus),
        userInfo: [
          NSLocalizedDescriptionKey: diagnostic.isEmpty
            ? String(
              localized:
                "\(process.executableURL!.lastPathComponent) exited with status \(process.terminationStatus)."
            )
            : diagnostic
        ])
    }
    return data
  }
}
