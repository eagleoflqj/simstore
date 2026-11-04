import AppKit
import SwiftUI

private struct ButtonFrames: PreferenceKey {
  static let defaultValue: [String: CGRect] = [:]

  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

@MainActor
private final class Measurements {
  var frames: [String: CGRect] = [:]
}

@main
struct StableSizeViewTests {
  @MainActor
  static func main() async {
    do {
      guard CommandLine.arguments.count == 2 else { throw failure("Expected the app bundle path.") }
      let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("Contents/Resources")
      let app = NSApplication.shared
      app.setActivationPolicy(.regular)
      let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 640, height: 180),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      var cases = 0
      for language in ["en", "zh-Hans"] {
        guard let bundle = Bundle(url: resources.appendingPathComponent("\(language).lproj")) else {
          throw failure("Missing \(language) translations.")
        }
        let checking = bundle.localizedString(forKey: "Checking…", value: nil, table: nil)
        for key in ["Check Again", "Try Again"] {
          let idle = bundle.localizedString(forKey: key, value: nil, table: nil)
          for controlSize: ControlSize in [.regular, .large] {
            for fontSize: CGFloat in [14, 24] {
              let labels = [idle, checking]
              let before = try await measure(
                window, checking: false, labels: labels, controlSize: controlSize,
                fontSize: fontSize)
              let during = try await measure(
                window, checking: true, labels: labels, controlSize: controlSize, fontSize: fontSize
              )
              for name in ["check", "neighbor"] {
                guard let first = before[name], let second = during[name],
                  abs(first.minX - second.minX) < 0.5,
                  abs(first.minY - second.minY) < 0.5,
                  abs(first.width - second.width) < 0.5,
                  abs(first.height - second.height) < 0.5
                else {
                  throw failure(
                    "\(language), \(key), \(controlSize), \(fontSize): \(name) moved or resized.")
                }
              }
              cases += 1
            }
          }
        }
      }
      print(
        "PASS: stable button bounds and adjacent position in \(cases) translated control/font combinations."
      )
    } catch {
      FileHandle.standardError.write(
        Data("Stable sizing test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  @MainActor
  private static func measure(
    _ window: NSWindow, checking: Bool, labels: [String], controlSize: ControlSize,
    fontSize: CGFloat
  ) async throws -> [String: CGRect] {
    let measurements = Measurements()
    let content = HStack(spacing: 10) {
      Button("Neighbor") {}.buttonStyle(.borderedProminent)
        .background(frame("neighbor"))
      Button {
      } label: {
        Label {
          StableSizeView(checking, states: [false, true]) { state in
            Text(verbatim: labels[state ? 1 : 0])
          }
        } icon: {
          Image(systemName: "arrow.clockwise")
        }
      }
      .buttonStyle(.bordered)
      .disabled(checking)
      .background(frame("check"))
    }
    .controlSize(controlSize)
    .font(.system(size: fontSize))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onPreferenceChange(ButtonFrames.self) { frames in
      Task { @MainActor in measurements.frames = frames }
    }
    let host = NSHostingView(rootView: content)
    host.frame = NSRect(x: 0, y: 0, width: 640, height: 180)
    window.contentView = host
    window.orderFront(nil)
    for _ in 0..<30 {
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(20))
      if measurements.frames.count == 2 { return measurements.frames }
    }
    throw failure("Native button geometry was not produced.")
  }

  private static func frame(_ name: String) -> some View {
    GeometryReader { geometry in
      Color.clear.preference(key: ButtonFrames.self, value: [name: geometry.frame(in: .global)])
    }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "StableSizeViewTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
