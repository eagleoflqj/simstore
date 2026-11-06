import Foundation

struct SelfUpdateClient: Sendable {
  var url = AppConfiguration.updateIndexURL
  var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
    try await URLSession.shared.data(for: $0)
  }

  func fetch() async throws -> SelfUpdateIndex {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.timeoutInterval = 30
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    let (data, response) = try await transport(request)
    try Task.checkCancellation()
    guard let response = response as? HTTPURLResponse else {
      throw AppDownload.Failure.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw AppDownload.Failure.httpStatus(response.statusCode)
    }
    return try SelfUpdateIndex.decode(data)
  }
}
