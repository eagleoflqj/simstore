import SwiftUI

@main
struct SimStoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("SimStore") {
            ContentView()
        }
        .defaultSize(width: 800, height: 540)
    }
}
