import SwiftUI

@MainActor
struct StableSizeView<State: Hashable, Content: View>: View {
  let selection: State
  let states: [State]
  let content: (State) -> Content

  init(
    _ selection: State, states: [State],
    @ViewBuilder content: @escaping (State) -> Content
  ) {
    self.selection = selection
    self.states = states
    self.content = content
  }

  var body: some View {
    ZStack {
      ForEach(states, id: \.self) { state in
        content(state)
          .opacity(state == selection ? 1 : 0)
          .allowsHitTesting(state == selection)
          .accessibilityHidden(state != selection)
      }
    }
  }
}
