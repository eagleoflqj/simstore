import SwiftUI

@MainActor
struct MissingXcodeView: View {
  let isChecking: Bool
  let openAppStore: () -> Void
  let checkAgain: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Image(systemName: "hammer")
        .font(.system(size: 58, weight: .light))
        .foregroundStyle(Color.accentColor)
        .frame(width: 130, height: 130)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 30))
        .padding(.bottom, 30)
      Text("Start with Xcode.")
        .font(.system(size: 25, weight: .semibold))
        .tracking(-0.6)
      Text(
        "Xcode provides the tools SimStore needs to run iOS apps.\nInstall it from the App Store, then open it to finish setup."
      )
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .lineSpacing(5)
      .padding(.top, 12)
      HStack(spacing: 10) {
        Button("Open App Store", systemImage: "bag", action: openAppStore)
          .buttonStyle(.borderedProminent)
        SimulatorCheckButton(isChecking: isChecking, action: checkAgain)
          .buttonStyle(.bordered)
      }
      .padding(.top, 25)
    }
    .padding(.horizontal, 30)
  }
}
