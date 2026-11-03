import CoreGraphics
import Foundation

@main
struct AppSmokeTest {
    static func main() {
        do {
            try verifyWindow()
        } catch {
            FileHandle.standardError.write(Data("App smoke test failed: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    static func verifyWindow() throws {
        guard CommandLine.arguments.count == 2 else {
            throw failure("Expected the App Bundle path.")
        }
        let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard let executable = Bundle(url: bundleURL)?.executableURL else {
            throw failure("The App Bundle has no executable.")
        }
        let process = Process()
        process.executableURL = executable
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }

        let deadline = Date().addingTimeInterval(10)
        var foundWindow = false
        while Date() < deadline {
            guard process.isRunning else {
                throw failure("The app exited before its window appeared (status \(process.terminationStatus)).")
            }
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            foundWindow = windows.contains { window in
                guard (window[kCGWindowOwnerPID as String] as? Int32) == process.processIdentifier,
                      (window[kCGWindowLayer as String] as? Int) == 0,
                      let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let width = bounds["Width"] as? Double,
                      let height = bounds["Height"] as? Double else {
                    return false
                }
                return width >= 600 && height >= 400
            }
            if foundWindow {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard foundWindow else {
            throw failure("No visible app window appeared. Run this test from a logged-in macOS GUI session.")
        }
        Thread.sleep(forTimeInterval: 2)
        guard process.isRunning else {
            throw failure("The app exited after showing its window.")
        }
        print("PASS: SimStore launched with a visible window and remained alive (PID \(process.processIdentifier)).")
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "SimStoreSmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
