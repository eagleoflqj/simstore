import AppKit
import SwiftUI

@MainActor
final class SelfUpdateController: NSObject, NSWindowDelegate {
  let store: SelfUpdateStore
  private(set) var panel: NSPanel?

  init(store: SelfUpdateStore = SelfUpdateStore()) {
    self.store = store
  }

  func show(check: Bool = false) {
    if panel == nil {
      let panel = NSPanel(
        contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
      panel.title = String(localized: "About SimStore")
      panel.isReleasedWhenClosed = false
      panel.isExcludedFromWindowsMenu = true
      panel.hidesOnDeactivate = false
      panel.tabbingMode = .disallowed
      panel.delegate = self
      panel.contentView = NSHostingView(
        rootView: SelfUpdateView(store: store) { [weak self] in
          self?.panel?.close()
        })
      if let view = panel.contentView { panel.setContentSize(view.fittingSize) }
      panel.center()
      self.panel = panel
    }
    panel?.makeKeyAndOrderFront(nil)
    if check { store.check() }
  }

  func showPendingFailure() {
    if store.consumeFailureReport() { show() }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard store.phase != nil else { return true }
    store.cancel()
    return false
  }
}
