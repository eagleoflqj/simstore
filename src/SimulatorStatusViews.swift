import SwiftUI

@MainActor
struct SimulatorLoadingView: View {
  var body: some View {
    VStack(spacing: 15) {
      ProgressView().controlSize(.small)
      Text("Looking for your simulators…")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    }
  }
}

@MainActor
struct SimulatorsReadyView: View {
  let count: Int

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "iphone.and.arrow.forward")
        .font(.system(size: 48, weight: .light))
        .foregroundStyle(Color.accentColor)
      Text("Your simulators are ready")
        .font(.system(size: 24, weight: .semibold))
      Text(
        "Found \(count) available iOS simulators."
      )
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
    }
  }
}

@MainActor
struct SimulatorDiscoveryErrorView: View {
  let error: Error
  let isChecking: Bool
  let openXcode: () -> Void
  let checkAgain: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 44, weight: .light))
        .foregroundStyle(.orange)
      Text("Couldn’t check for simulators")
        .font(.system(size: 24, weight: .semibold))
      Text(
        "Make sure Xcode is installed and its command-line tools are selected, then try again."
      )
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 390)
      HStack(spacing: 10) {
        Button("Open Xcode", systemImage: "hammer") { openXcode() }
        SimulatorCheckButton(isChecking: isChecking, isRetry: true, action: checkAgain)
      }
      .controlSize(.large)
      DisclosureGroup("Details") {
        Text(error.localizedDescription)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 8)
      }
      .font(.system(size: 11))
      .frame(maxWidth: 390)
    }
    .padding(30)
  }
}
