import SwiftUI

struct DiscoverHeading: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Discover")
        .font(.system(size: 30, weight: .bold))
        .tracking(-0.8)
      Text("Open-source favorites. Built for your simulator.")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    }
  }
}
