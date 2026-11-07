import SwiftUI

struct CatalogAppGrid<Content: View>: View {
  let apps: [CatalogApp]
  private let content: (CatalogApp, FocusState<String?>.Binding) -> Content
  @FocusState private var focusedAppID: String?

  init(
    apps: [CatalogApp],
    @ViewBuilder content: @escaping (CatalogApp, FocusState<String?>.Binding) -> Content
  ) {
    self.apps = apps
    self.content = content
  }

  var body: some View {
    GeometryReader { geometry in
      let count = max(1, Int((geometry.size.width + 16) / 280))
      let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16), count: count)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(apps) { app in
              content(app, $focusedAppID)
                .id(app.id)
            }
          }
          .padding(3)
          .padding(.bottom, 24)
        }
        .defaultScrollAnchor(.top)
        .onChange(of: focusedAppID) { _, id in
          if let id { proxy.scrollTo(id, anchor: .center) }
        }
      }
    }
  }
}
