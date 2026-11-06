import SwiftUI

enum LibrarySection: String, CaseIterable {
  case discover, installed, updates

  var title: String {
    switch self {
    case .discover: String(localized: "Discover")
    case .installed: String(localized: "Installed")
    case .updates: String(localized: "Updates")
    }
  }

  var subtitle: String {
    switch self {
    case .discover: String(localized: "Open-source favorites. Built for your simulator.")
    case .installed: String(localized: "Apps from the catalog on this simulator.")
    case .updates: String(localized: "Newer versions for your simulator.")
    }
  }

  var symbolName: String {
    switch self {
    case .discover: "safari"
    case .installed: "square.grid.2x2"
    case .updates: "arrow.triangle.2.circlepath"
    }
  }
}

struct LibraryHeading: View {
  let section: LibrarySection

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(verbatim: section.title)
        .font(.system(size: 30, weight: .bold))
        .tracking(-0.8)
      Text(verbatim: section.subtitle)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    }
  }
}
