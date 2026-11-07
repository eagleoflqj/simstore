import AppKit
import SwiftUI

private struct CardFrames: PreferenceKey {
  static let defaultValue: [String: CGRect] = [:]

  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

@MainActor
private final class GridProbe {
  var appeared: Set<String> = []
  var frames: [String: CGRect] = [:]
  var focus: FocusState<String?>.Binding?
}

@MainActor
private struct GridFixture: View {
  let apps: [CatalogApp]
  let probe: GridProbe

  var body: some View {
    CatalogAppGrid(apps: apps) { app, focus in
      // Editable controls receive keyboard focus independently of global button navigation.
      TextField(app.name, text: .constant(app.name))
        .textFieldStyle(.roundedBorder)
        .focused(focus, equals: app.id)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background {
          GeometryReader { geometry in
            Color.clear.preference(
              key: CardFrames.self,
              value: [app.id: geometry.frame(in: .named("grid-fixture"))])
          }
        }
        .onAppear {
          probe.appeared.insert(app.id)
          probe.focus = focus
        }
    }
    .coordinateSpace(name: "grid-fixture")
    .onPreferenceChange(CardFrames.self) { frames in
      Task { @MainActor in probe.frames = frames }
    }
  }
}

@main
@MainActor
struct CatalogAppGridTests {
  static func main() {
    NSApplication.shared.setActivationPolicy(.regular)
    Task { @MainActor in
      do {
        let apps = (0..<1000).map(app)
        let keyboard = CommandLine.arguments.contains("--keyboard")
        let probe = GridProbe()
        let host = NSHostingView(rootView: GridFixture(apps: apps, probe: probe))
        let window = NSWindow(
          contentRect: NSRect(x: 200, y: 200, width: 600, height: 360),
          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        if keyboard {
          window.makeKeyAndOrderFront(nil)
          NSApplication.shared.activate()
        } else {
          window.orderFront(nil)
        }
        defer { window.close() }
        try await eventually { (probe.frames[apps[0].id]?.width ?? 0) > 200 }
        try require(
          probe.appeared.count < 100 && !probe.appeared.contains(apps[900].id),
          "A large catalog must not create every card when first displayed.")
        guard let scroll = scrollView(in: host) else {
          throw failure("Missing the grid scroll view.")
        }
        try checkColumns(probe, apps: apps, columns: 2, width: scroll.contentView.bounds.width)
        if keyboard {
          try await eventually { window.isKeyWindow && NSApplication.shared.isActive }
          probe.focus?.wrappedValue = apps[0].id
          try await eventually { probe.focus?.wrappedValue == apps[0].id }
          for index in 1...40 {
            let event = NSEvent.keyEvent(
              with: .keyDown, location: .zero, modifierFlags: [],
              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
              context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
              isARepeat: false, keyCode: 48)!
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(40))
            try await eventually { probe.focus?.wrappedValue == apps[index].id }
            try await eventually { isVisible(apps[index].id, in: probe) }
            try await Task.sleep(for: .milliseconds(20))
          }
        }
        scrollToEnd(scroll, bottom: true)
        try await eventually { isVisible(apps[999].id, in: probe) }
        if keyboard {
          probe.focus?.wrappedValue = apps[999].id
          try await eventually { probe.focus?.wrappedValue == apps[999].id }
          try require(
            isVisible(apps[999].id, in: probe),
            "Scrolling to a lazy card must preserve its keyboard focus.")
        }
        try require(
          probe.appeared.count < 200,
          "Jumping to a distant card must not create all intervening cards.")
        scrollToEnd(scroll, bottom: false)
        try await eventually {
          guard let frame = probe.frames[apps[0].id] else { return false }
          return frame.minY >= 0 && frame.maxY <= 360
        }
        if keyboard { probe.focus?.wrappedValue = apps[0].id }
        window.setContentSize(NSSize(width: 900, height: 360))
        try await eventually {
          guard let first = probe.frames[apps[0].id], let third = probe.frames[apps[2].id] else {
            return false
          }
          let expected = (scroll.contentView.bounds.width - 6 - 2 * 16) / 3
          return scroll.contentView.bounds.width > 850
            && abs(first.minY - third.minY) < 0.5 && abs(first.width - expected) < 0.5
        }
        try checkColumns(probe, apps: apps, columns: 3, width: scroll.contentView.bounds.width)
        print(
          "PASS: lazy catalog creation, distant scrolling, and responsive equal-width columns."
        )
        if keyboard {
          print("PASS: native key-view navigation and focus scrolling across lazy rows.")
        }
      } catch {
        FileHandle.standardError.write(
          Data("Catalog grid test failed: \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
      }
      exit(EXIT_SUCCESS)
    }
    NSApplication.shared.run()
  }

  private static func isVisible(_ id: String, in probe: GridProbe) -> Bool {
    guard let frame = probe.frames[id] else { return false }
    return frame.midY > 0 && frame.midY < 360
  }

  private static func scrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
  }

  private static func scrollToEnd(_ scroll: NSScrollView, bottom: Bool) {
    guard let document = scroll.documentView else { return }
    let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
    let y = bottom == document.isFlipped ? maximum : 0
    scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
    scroll.reflectScrolledClipView(scroll.contentView)
  }

  private static func checkColumns(
    _ probe: GridProbe, apps: [CatalogApp], columns: Int, width: CGFloat
  ) throws {
    let expected = (width - 6 - CGFloat(columns - 1) * 16) / CGFloat(columns)
    for index in 0..<columns {
      guard let frame = probe.frames[apps[index].id] else {
        throw failure("Missing a visible card.")
      }
      try require(
        abs(frame.width - expected) < 0.5
          && abs(frame.minX - (3 + CGFloat(index) * (expected + 16))) < 0.5,
        "Keep equal column widths, 16 pt spacing, and room for focus rings: card \(index), frame \(frame), expected width \(expected)."
      )
    }
  }

  private static func app(_ index: Int) -> CatalogApp {
    CatalogApp(
      id: "app\(index)", name: "App \(index)", bundleID: "org.example.App\(index)",
      repository: URL(string: "https://example.com/app")!, license: "MIT",
      description: ["en": "An app."], categories: ["utilities"],
      versions: [
        CatalogVersion(
          version: "1.0", minSimulatorOS: "14.0", sha256: String(repeating: "a", count: 64),
          size: 1, revision: String(repeating: "b", count: 40),
          recipeRevision: String(repeating: "c", count: 40), time: 0)
      ])
  }

  private static func eventually(_ condition: () -> Bool, line: UInt = #line) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition() {
      guard ContinuousClock.now < deadline else {
        throw failure("Timed out waiting for lazy grid layout or focus at line \(line).")
      }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw failure(message) }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "CatalogAppGridTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
