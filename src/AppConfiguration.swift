import Foundation

enum AppConfiguration {
  static let applicationIdentifier =
    Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
  static let buildsRepositoryURL = URL(string: "https://github.com/iSimStore/simstore-builds")!

  static var catalogURL: URL {
    buildsRepositoryURL.appending(path: "releases/download/latest/index.json")
  }

  static func releaseURL(appID: String, version: String) -> URL {
    buildsRepositoryURL.appending(path: "releases/tag").appending(component: "\(appID)/\(version)")
  }

  static func commitURL(repository: URL, revision: String) -> URL {
    repository.appending(path: "commit").appending(component: revision)
  }

  static func assetURL(appID: String, version: String, filename: String) -> URL {
    buildsRepositoryURL.appending(path: "releases/download")
      .appending(component: "\(appID)/\(version)").appending(component: filename)
  }
}
