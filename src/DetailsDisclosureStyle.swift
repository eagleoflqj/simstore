import SwiftUI

struct DetailsDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation { configuration.isExpanded.toggle() }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
            .accessibilityHidden(true)
          configuration.label
          Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if configuration.isExpanded {
        configuration.content.padding(.leading, 16)
      }
    }
  }
}
