import Foundation

@main
struct CatalogCategoriesCheck {
  static func main() async {
    do {
      let url = AppConfiguration.catalogURL
      var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
      request.timeoutInterval = 30
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let response = response as? HTTPURLResponse else {
        throw failure("Expected an HTTP response from \(url).")
      }
      guard response.statusCode == 200 else {
        throw failure("The latest catalog returned HTTP \(response.statusCode).")
      }
      let catalog = try AppCatalog.decode(data)
      var missing: [String: [String]] = [:]
      for app in catalog.apps {
        for category in app.categories where CatalogCategory(rawValue: category) == nil {
          missing[category, default: []].append(app.id)
        }
      }
      guard missing.isEmpty else {
        let details = missing.keys.sorted().map { category in
          "  \(category): \(missing[category]!.sorted().joined(separator: ", "))"
        }
        throw failure(
          "Unlisted catalog categories:\n\(details.joined(separator: "\n"))\nAdd them to CatalogCategory and translate their titles."
        )
      }
      let categories = Set(catalog.apps.flatMap(\.categories))
      print(
        "PASS: all \(categories.count) categories across \(catalog.apps.count) apps in \(url) are declared."
      )
    } catch {
      FileHandle.standardError.write(
        Data("Catalog category check failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(
      domain: "CatalogCategoriesCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
