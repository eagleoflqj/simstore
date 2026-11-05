import Foundation
import OSLog

struct CatalogClient: Sendable {
  typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  let url: URL
  let cacheURL: URL
  private let transport: Transport

  static let live = CatalogClient(
    url: AppConfiguration.catalogURL,
    cacheURL: URL.cachesDirectory.appending(component: AppConfiguration.applicationIdentifier)
      .appending(component: "index.json")
  )

  init(
    url: URL,
    cacheURL: URL,
    transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
  ) {
    self.url = url
    self.cacheURL = cacheURL
    self.transport = transport
  }

  func loadCached() async throws -> AppCatalog? {
    let cacheURL = cacheURL
    return try await Task.detached(priority: .utility) {
      guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
      return try AppCatalog.decode(Data(contentsOf: cacheURL))
    }.value
  }

  func fetch() async throws -> AppCatalog {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.timeoutInterval = 30
    let (data, response) = try await transport(request)
    try Task.checkCancellation()
    guard let response = response as? HTTPURLResponse else {
      throw CatalogDownloadError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw CatalogDownloadError.httpStatus(response.statusCode)
    }
    let catalog = try AppCatalog.decode(data)
    let cacheURL = cacheURL
    await Task.detached(priority: .utility) {
      do {
        try FileManager.default.createDirectory(
          at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
      } catch {
        Logger(subsystem: AppConfiguration.applicationIdentifier, category: "Catalog")
          .error("Could not save catalog cache: \(error.localizedDescription, privacy: .public)")
      }
    }.value
    try Task.checkCancellation()
    return catalog
  }
}

private enum CatalogDownloadError: LocalizedError {
  case invalidResponse
  case httpStatus(Int)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      String(localized: "The app repository returned an invalid response.")
    case .httpStatus(let status):
      String(localized: "The app repository returned HTTP \(status).")
    }
  }
}
