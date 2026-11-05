import AppKit

enum SimulatorPresenter {
  struct Request: Equatable, Sendable {
    let applicationURL: URL
    let urls: [URL]
    let arguments: [String]
  }

  static func request(deviceID: String, manager: (name: String, url: URL)?) throws -> Request {
    guard let manager else {
      throw NSError(
        domain: "SimulatorPresenter", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: String(
            localized:
              "The simulator application could not be found. Check your Xcode installation.")
        ])
    }
    if manager.url.lastPathComponent == "DeviceHub.app" {
      var components = URLComponents()
      components.scheme = "devices"
      components.host = "device"
      components.path = "/open"
      components.queryItems = [URLQueryItem(name: "id", value: deviceID)]
      return Request(applicationURL: manager.url, urls: [components.url!], arguments: [])
    }
    return Request(
      applicationURL: manager.url, urls: [], arguments: ["-CurrentDeviceUDID", deviceID])
  }

  @MainActor
  static func show(deviceID: String, manager: (name: String, url: URL)?) async throws {
    let request = try request(deviceID: deviceID, manager: manager)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.allowsRunningApplicationSubstitution = false
    configuration.arguments = request.arguments
    if request.urls.isEmpty {
      _ = try await NSWorkspace.shared.openApplication(
        at: request.applicationURL, configuration: configuration)
    } else {
      _ = try await NSWorkspace.shared.open(
        request.urls, withApplicationAt: request.applicationURL, configuration: configuration)
    }
  }
}
