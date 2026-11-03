import AppKit
import SwiftUI

@MainActor
struct ContentView: View {
    @State private var cannotOpenRepository = false

    private let repositoryURL = URL(string: "https://github.com/eagleoflqj/simstore-builds")!

    var body: some View {
        ContentUnavailableView {
            Label("SimStore", systemImage: "square.stack.3d.up.fill")
        } description: {
            Text("Open-source apps for iOS Simulator.")
        } actions: {
            Button("View App Repository", systemImage: "arrow.up.right") {
                cannotOpenRepository = !NSWorkspace.shared.open(repositoryURL)
            }
            .controlSize(.large)
        }
        .frame(minWidth: 640, minHeight: 420)
        .alert("Couldn’t Open Repository", isPresented: $cannotOpenRepository) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open this address in your web browser: \(repositoryURL.absoluteString)")
        }
    }
}
