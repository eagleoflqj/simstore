import Foundation

enum AppConfiguration {
  static let applicationIdentifier =
    Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
  static let cacheDirectory = URL.cachesDirectory.appending(component: applicationIdentifier)
  static let buildsRepositoryURL = URL(string: "https://github.com/iSimStore/simstore-builds")!
  static let repositoryURL = URL(string: "https://github.com/iSimStore/simstore")!
  static let archiveName = "SimStore.app.tar.bz2"

  static var updateIndexURL: URL {
    updateAssetURL(tag: "latest", filename: "version.json")
  }

  static func updateAssetURL(tag: String, filename: String) -> URL {
    repositoryURL.appending(path: "releases/download").appending(component: tag)
      .appending(component: filename)
  }

  static var catalogURL: URL {
    buildsRepositoryURL.appending(path: "releases/download/latest/index.json")
  }

  static func releaseURL(appID: String, version: String) -> URL {
    buildsRepositoryURL.appending(path: "releases/tag").appending(component: "\(appID)/\(version)")
  }

  static func commitURL(repository: URL, revision: String) -> URL {
    repository.appending(path: "commit").appending(component: revision)
  }

  static func manifestURL(appID: String, revision: String) -> URL {
    buildsRepositoryURL.appending(path: "blob").appending(component: revision)
      .appending(path: "apps").appending(component: appID).appending(component: "manifest.yaml")
  }

  static func assetURL(appID: String, version: String, filename: String) -> URL {
    buildsRepositoryURL.appending(path: "releases/download")
      .appending(component: "\(appID)/\(version)").appending(component: filename)
  }
}
