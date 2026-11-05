import Foundation

enum Command {
  typealias Runner = @Sendable (String, [String]) throws -> Data

  static let xcrunExecutable = "/usr/bin/xcrun"
  static let simctlTool = "simctl"

  static func run(_ executable: String, arguments: [String]) throws -> Data {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      let diagnostic = String(decoding: data, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      throw NSError(
        domain: "Command", code: Int(process.terminationStatus),
        userInfo: [
          NSLocalizedDescriptionKey: diagnostic.isEmpty
            ? String(
              localized:
                "\(process.executableURL!.lastPathComponent) exited with status \(process.terminationStatus)."
            )
            : diagnostic
        ])
    }
    return data
  }

  static func xcrun(_ arguments: [String], using command: Runner = run) throws -> Data {
    try command(xcrunExecutable, arguments)
  }

  static func simctl(_ arguments: [String], using command: Runner = run) throws -> Data {
    try xcrun([simctlTool] + arguments, using: command)
  }
}
