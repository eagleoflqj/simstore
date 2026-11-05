import SwiftUI

enum CatalogCategory {
  static func title(_ category: String) -> String {
    switch category {
    case "browser": String(localized: "Browser")
    case "cloud": String(localized: "Cloud")
    case "communication": String(localized: "Communication")
    case "media": String(localized: "Media")
    case "productivity": String(localized: "Productivity")
    case "security": String(localized: "Security")
    case "social": String(localized: "Social")
    case "utilities": String(localized: "Utilities")
    default: category
    }
  }
}

extension CatalogApp {
  var displayDescription: String {
    localizedDescription(preferredLanguages: Bundle.main.preferredLocalizations)
  }

  var categoryTitle: String {
    categories.map(CatalogCategory.title).joined(separator: " · ")
  }
}

extension CatalogVersion {
  var minimumOSLabel: String {
    String(localized: "iOS \(minSimulatorOS) or later")
  }
}

extension SimulatorApplication {
  var displayVersion: String { version ?? String(localized: "Version Unavailable") }
}

struct CatalogIcon: View {
  let app: CatalogApp
  var size: CGFloat = 52
  @State private var image: CGImage?

  private var key: IconCache.Key {
    IconCache.Key(
      url: AppConfiguration.assetURL(
        appID: app.id, version: app.latestVersion.version, filename: "icon.png"),
      recipeRevision: app.latestVersion.recipeRevision)
  }

  var body: some View {
    let key = key
    Group {
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
      } else {
        RoundedRectangle(cornerRadius: size * 0.22)
          .fill(Color.accentColor.opacity(0.08))
          .overlay {
            Image(systemName: "app.dashed")
              .font(.system(size: size * 0.45, weight: .light))
              .foregroundStyle(.secondary)
          }
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    .accessibilityHidden(true)
    .task(id: key) {
      guard !Task.isCancelled else { return }
      image = nil
      do {
        let loaded = try await IconCache.shared.image(for: key)
        try Task.checkCancellation()
        image = loaded
      } catch {}
    }
  }
}

struct CatalogRefreshButton: View {
  let isLoading: Bool
  let refresh: () -> Void

  var body: some View {
    Button(action: refresh) {
      Label {
        Text("Refresh Catalog")
      } icon: {
        StableSizeView(isLoading, states: [false, true]) { loading in
          if loading {
            ProgressView().controlSize(.mini)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
    }
    .disabled(isLoading)
  }
}
