import AppKit

@main
struct AppLifecycleTest {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 640, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard window.isVisible else {
                fatalError("The test window did not appear.")
            }
            print("Closing the last window; the process must exit normally.")
            window.performClose(nil)
        }
        withExtendedLifetime(delegate) {
            application.run()
        }
        fatalError("The application event loop returned without terminating the process.")
    }
}
