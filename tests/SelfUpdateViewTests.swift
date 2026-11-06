import AppKit

enum SelfUpdateViewTests {
  @MainActor
  static func run() async throws {
    _ = NSApplication.shared
    let stable = try SelfUpdateFixtures.release()
    let nightly = try SelfUpdateFixtures.release(["tag": "latest", "build": 8])
    for installed in [SelfUpdateFixtures.current(), SelfUpdateFixtures.current(version: "0.2.0")] {
      var client = SelfUpdateClient()
      let data = try SelfUpdateFixtures.index([stable, nightly])
      client.transport = { request in
        (
          data,
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      }
      let store = SelfUpdateStore(current: installed, os: "14.0", client: client)
      let controller = SelfUpdateController(store: store)
      controller.show(check: true)
      defer { controller.panel?.close() }
      try await SelfUpdateFixtures.eventually { !store.isBusy }
      try await Task.sleep(for: .milliseconds(100))
      guard let panel = controller.panel, let view = panel.contentView else {
        throw SelfUpdateFixtures.failure("The About/update panel must exist.")
      }
      view.layoutSubtreeIfNeeded()
      try SelfUpdateFixtures.require(
        panel.frame.width >= 460 && panel.frame.height > 300 && panel.frame.height < 650,
        "Fit the About and update content without a resizable main window.")
      try SelfUpdateFixtures.require(
        !panel.canBecomeMain && panel.tabbingMode == .disallowed && panel.isExcludedFromWindowsMenu,
        "Keep the auxiliary panel separate from main-window navigation.")
      let buttons = nativeButtons(in: view)
      try SelfUpdateFixtures.require(
        buttons.count >= 2, "Expose native buttons for keyboard and accessibility navigation.")
      for button in buttons {
        let frame = view.convert(button.bounds, from: button)
        try SelfUpdateFixtures.require(
          view.bounds.insetBy(dx: -1, dy: -1).contains(frame),
          "Keep every action button inside the panel.")
      }
      panel.performClose(nil)
      try SelfUpdateFixtures.require(!panel.isVisible, "An idle update panel must close normally.")
    }
    print(
      "PASS: About/update panels fit stable and nightly content and do not add main windows or tabs."
    )
  }
  @MainActor
  private static func nativeButtons(in view: NSView) -> [NSButton] {
    view.subviews.flatMap { child in
      (child as? NSButton).map { [$0] } ?? nativeButtons(in: child)
    }
  }

}
