import Foundation

enum AppConfiguration {
  static let applicationIdentifier =
    Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
  static let buildsRepositoryURL = URL(string: "https://github.com/iSimStore/simstore-builds")!

  static var catalogURL: URL {
    buildsRepositoryURL.appending(path: "releases/download/latest/index.json")
  }

  static func assetURL(appID: String, version: String, filename: String) -> URL {
    buildsRepositoryURL.appending(path: "releases/download")
      .appending(component: "\(appID)/\(version)").appending(component: filename)
  }
}
