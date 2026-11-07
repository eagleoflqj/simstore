import AppKit
import Observation

@MainActor
@Observable
final class SelfUninstallController {
  private(set) var isRunning = false
  @ObservationIgnored private let application: URL
  @ObservationIgnored private let uninstall: @MainActor () async throws -> Void
  @ObservationIgnored private let failureTitle = String(localized: "Couldn’t Uninstall SimStore")

  init(
    application: URL = Bundle.main.bundleURL,
    uninstall: @escaping @MainActor () async throws -> Void = SelfUninstaller.start
  ) {
    self.application = application
    self.uninstall = uninstall
  }

  func confirm(beforeUninstall: () -> Void = {}) {
    guard !isRunning else { return }
    isRunning = true
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = String(localized: "Uninstall SimStore?")
    alert.informativeText =
      String(
        localized:
          "SimStore, its caches, settings, and temporary files will be permanently deleted. SimStore will then quit."
      )
      + "\n\n" + application.path
    alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
    alert.addButton(withTitle: String(localized: "Uninstall")).hasDestructiveAction = true
    guard alert.runModal() == .alertSecondButtonReturn else {
      isRunning = false
      return
    }
    beforeUninstall()
    Task {
      defer { isRunning = false }
      do {
        try await uninstall()
      } catch {
        let failure = NSAlert()
        failure.alertStyle = .warning
        failure.messageText = failureTitle
        failure.informativeText = error.localizedDescription
        failure.addButton(withTitle: String(localized: "OK"))
        failure.runModal()
      }
    }
  }
}
