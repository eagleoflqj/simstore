import AppKit
import CoreGraphics

@main
struct AppSmokeTest {
  @MainActor
  static func main() async {
    do {
      try await verifyWindow()
    } catch {
      FileHandle.standardError.write(
        Data("App smoke test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  @MainActor
  static func verifyWindow() async throws {
    guard CommandLine.arguments.count == 2 else {
      throw failure("Expected the App Bundle path.")
    }
    let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    let application = try await NSWorkspace.shared.openApplication(
      at: bundleURL, configuration: configuration)
    defer { application.terminate() }

    let deadline = Date().addingTimeInterval(10)
    var foundWindow = false
    while Date() < deadline {
      guard !application.isTerminated else {
        throw failure(
          "The app exited before its window appeared.")
      }
      let windows =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
      foundWindow = windows.contains { window in
        guard (window[kCGWindowOwnerPID as String] as? Int32) == application.processIdentifier,
          (window[kCGWindowLayer as String] as? Int) == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double
        else {
          return false
        }
        return width >= 600 && height >= 400
      }
      if foundWindow {
        break
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    guard foundWindow else {
      throw failure(
        "No visible app window appeared. Run this test from a logged-in macOS GUI session.")
    }
    try await Task.sleep(for: .seconds(2))
    guard !application.isTerminated else {
      throw failure("The app exited after showing its window.")
    }
    print(
      "PASS: SimStore launched with a visible window and remained alive (PID \(application.processIdentifier))."
    )
  }

  static func failure(_ message: String) -> NSError {
    NSError(domain: "SimStoreSmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
