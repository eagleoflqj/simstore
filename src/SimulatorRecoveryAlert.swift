import AppKit
import SwiftUI

struct SimulatorRecoveryAlert: ViewModifier {
  let monitor: SimulatorOperationMonitor
  let shutdown: (String) -> Void

  func body(content: Content) -> some View {
    content.background {
      RecoveryPresenter(monitor: monitor, prompt: monitor.prompt, shutdown: shutdown)
        .frame(width: 0, height: 0)
    }
  }
}

private struct RecoveryPresenter: NSViewRepresentable {
  let monitor: SimulatorOperationMonitor
  let prompt: SimulatorOperationMonitor.Prompt?
  let shutdown: (String) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(monitor: monitor) }

  func makeNSView(context: Context) -> AnchorView {
    let view = AnchorView()
    view.windowChanged = { [weak coordinator = context.coordinator] window in
      coordinator?.updateWindow(window)
    }
    return view
  }

  func updateNSView(_ view: AnchorView, context: Context) {
    context.coordinator.update(prompt: prompt, shutdown: shutdown, window: view.window)
  }

  static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
    view.windowChanged = nil
    coordinator.dismiss()
  }

  final class AnchorView: NSView {
    var windowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      windowChanged?(window)
    }
  }

  @MainActor
  final class Coordinator {
    private let monitor: SimulatorOperationMonitor
    private var prompt: SimulatorOperationMonitor.Prompt?
    private var shutdown: (String) -> Void = { _ in }
    private weak var window: NSWindow?
    private var alert: NSAlert?
    private var presentedID: UUID?

    init(monitor: SimulatorOperationMonitor) { self.monitor = monitor }

    func update(
      prompt: SimulatorOperationMonitor.Prompt?, shutdown: @escaping (String) -> Void,
      window: NSWindow?
    ) {
      self.prompt = prompt
      self.shutdown = shutdown
      updateWindow(window)
    }

    func updateWindow(_ window: NSWindow?) {
      if self.window !== window || presentedID != prompt?.id { dismiss() }
      self.window = window
      guard alert == nil, let window, let prompt else { return }
      let alert = NSAlert()
      alert.messageText = String(localized: "Operation Is Taking Longer Than Expected")
      alert.informativeText = String(
        localized:
          "An app operation on \(prompt.device.name) hasn’t finished. Keep waiting, or shut down this simulator to stop pending operations. Shutting down closes all of its apps."
      )
      alert.addButton(withTitle: String(localized: "Keep Waiting")).keyEquivalent = "\u{1b}"
      alert.addButton(withTitle: String(localized: "Shut Down")).hasDestructiveAction = true
      // Direct sheet presentation bypasses NSAlert's usual pre-display layout.
      alert.layout()
      self.alert = alert
      presentedID = prompt.id
      // Recovery must remain available above the app details sheet.
      window.beginCriticalSheet(alert.window) { [weak self, weak alert] response in
        guard let self, let alert, self.alert === alert else { return }
        self.alert = nil
        presentedID = nil
        monitor.keepWaiting(prompt)
        if response == .alertSecondButtonReturn { shutdown(prompt.device.id) }
      }
    }

    func dismiss() {
      let previous = alert
      alert = nil
      presentedID = nil
      if let previous {
        previous.window.sheetParent?.endSheet(previous.window, returnCode: .abort)
        previous.window.orderOut(nil)
      }
    }
  }
}
