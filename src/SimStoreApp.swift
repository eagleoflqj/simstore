import SwiftUI

@main
struct SimStoreApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var updates = SelfUpdateController()

  var body: some Scene {
    Window(Text(verbatim: "SimStore"), id: "main") {
      ContentView()
        .task { updates.showPendingFailure() }
    }
    .defaultSize(width: 1180, height: 780)
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("About SimStore") { updates.show() }
      }
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") { updates.show(check: true) }
      }
    }
  }
}
