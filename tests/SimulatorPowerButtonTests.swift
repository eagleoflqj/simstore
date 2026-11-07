import AppKit
import SwiftUI

@main
@MainActor
struct SimulatorPowerButtonTests {
  static func main() async {
    do {
      NSApplication.shared.setActivationPolicy(.regular)
      let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 420, height: 100),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      var starts = 0
      var shutdowns = 0
      for size: ControlSize in [.regular, .small] {
        var results: [(frame: CGRect, enabled: Bool)] = []
        for state in ["Shutdown", "Booting", "Booted", "Shutting Down"] {
          let device = SimulatorDevice(id: "A", name: "iPhone", runtime: "27.0", state: state)
          let host = NSHostingView(
            rootView: SimulatorPowerButton(
              device: device,
              start: { starts += 1 }, shutdown: { shutdowns += 1 }
            )
            .controlSize(size)
            .frame(width: 420, height: 100, alignment: .leading))
          window.contentView = host
          window.orderFront(nil)
          let button = try await nativeButton(in: host)
          results.append((host.convert(button.bounds, from: button), button.isEnabled))
          button.performClick(nil)
        }
        try require(
          results.map(\.enabled) == [true, false, true, false],
          "Power actions depend only on device state; a booted simulator can always shut down.")
        for (idle, pending) in [(0, 1), (2, 3)] {
          let a = results[idle].frame
          let b = results[pending].frame
          try require(
            abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
              && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5,
            "Power actions must keep stable bounds while starting or shutting down.")
        }
      }
      try require(
        starts == 2 && shutdowns == 2,
        "Native buttons must invoke the matching action and ignore disabled clicks.")
      print(
        "PASS: native simulator power actions, device state gating, and stable transition bounds.")
    } catch {
      FileHandle.standardError.write(
        Data("Simulator power button test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  private static func nativeButton(in view: NSView) async throws -> NSButton {
    for _ in 0..<25 {
      view.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(20))
      if let button = findButton(in: view) { return button }
    }
    throw failure("The power action must expose a native button.")
  }

  private static func findButton(in view: NSView) -> NSButton? {
    if let button = view as? NSButton { return button }
    for child in view.subviews {
      if let button = findButton(in: child) { return button }
    }
    return nil
  }

  private static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw failure(message) }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(
      domain: "SimulatorPowerButtonTests", code: 1,
      userInfo: [NSLocalizedDescriptionKey: message])
  }
}
