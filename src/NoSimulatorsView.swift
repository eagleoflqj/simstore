import SwiftUI

@MainActor
struct NoSimulatorsView: View {
  let deviceManagerName: String?
  let isChecking: Bool
  let openDeviceManager: () -> Void
  let openXcode: () -> Void
  let checkAgain: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0)],
              center: .center, startRadius: 35, endRadius: 125)
          )
          .frame(width: 250, height: 200)
        Image(systemName: "ipad.landscape")
          .font(.system(size: 78, weight: .ultraLight))
          .foregroundStyle(Color.secondary.opacity(0.25))
          .rotationEffect(.degrees(-9))
          .offset(x: -35, y: 12)
        Image(systemName: "iphone.gen3")
          .font(.system(size: 112, weight: .ultraLight))
          .foregroundStyle(Color.accentColor.opacity(0.85))
          .rotationEffect(.degrees(9))
          .offset(x: 36, y: -6)
      }
      .accessibilityHidden(true)

      Text("A simulator is where it starts.")
        .font(.system(size: 25, weight: .semibold))
        .tracking(-0.6)
        .padding(.top, 6)
      Text(
        "Create an iPhone or iPad simulator in \(deviceManagerName ?? "Xcode").\nThen come back to find your next favorite app."
      )
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .lineSpacing(5)
      .padding(.top, 12)

      HStack(spacing: 10) {
        Button(
          "Open \(deviceManagerName ?? "Xcode")",
          systemImage: deviceManagerName == nil ? "hammer" : "iphone.and.arrow.forward"
        ) {
          openDeviceManager()
        }
        .buttonStyle(.borderedProminent)
        SimulatorCheckButton(isChecking: isChecking, action: checkAgain)
          .buttonStyle(.bordered)
      }
      .controlSize(.large)
      .padding(.top, 25)

      if deviceManagerName != nil {
        Button {
          openXcode()
        } label: {
          HStack(spacing: 5) {
            Text("Open Xcode")
            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
          }
          .font(.system(size: 11))
        }
        .buttonStyle(.link)
        .padding(.top, 18)
      } else {
        Text("Device Hub or Simulator couldn’t be found in the selected Xcode installation.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .padding(.top, 18)
      }
    }
    .padding(.horizontal, 30)
  }
}
