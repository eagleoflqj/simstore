import SwiftUI

@MainActor
struct SimulatorCheckButton: View {
  let isChecking: Bool
  var isRetry = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label {
        StableSizeView(isChecking, states: [false, true]) { checking in
          Text(title(for: checking))
        }
      } icon: {
        Image(systemName: "arrow.clockwise")
      }
    }
    .disabled(isChecking)
  }

  private func title(for checking: Bool) -> LocalizedStringKey {
    if checking { return "Checking…" }
    return isRetry ? "Try Again" : "Check Again"
  }
}
