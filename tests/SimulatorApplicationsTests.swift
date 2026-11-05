import Foundation

@main
struct SimulatorApplicationsTests {
  @MainActor
  static func main() async {
    do {
      try decodeFormats()
      try rejectInvalidResponses()
      try await querySelectedDevice()
      try await preserveCommandFailure()
      try await rejectStoppedDevices()
      try await cancelledBeforeQuery()
      try await cancelledDuringQuery()
      print(
        "PASS: installed-app formats, exact device query, failures, device state, and cancellation."
      )
    } catch {
      FileHandle.standardError.write(
        Data("Simulator applications test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  static let device = SimulatorDevice(
    id: "1140AE85-B348-46DB-AD13-2B18AAD499B4", name: "iPhone Test", runtime: "27.0",
    state: "Booted")

  static let listing = Data(
    """
    {
      "com.example.First" = {
        ApplicationType = User;
        CFBundleIdentifier = "com.example.First";
        CFBundleShortVersionString = "1.2.3";
        Path = "/Users/test/Devices/1140AE85/data/Containers/Bundle/Application/ABC/First.app";
      };
      "com.apple.mobilesafari" = {
        ApplicationType = System;
        CFBundleIdentifier = "com.apple.mobilesafari";
      };
    }
    """.utf8)

  static func decodeFormats() throws {
    let expected: Set<String> = ["com.example.First", "com.apple.mobilesafari"]
    try require(
      try SimulatorApplications.decodeBundleIDs(listing) == expected,
      "Decode actual simctl-style OpenStep dictionaries, including system apps.")
    let applications = [
      "com.example.First": ["CFBundleIdentifier": "com.example.First"],
      "com.apple.mobilesafari": ["ApplicationType": "System"],
    ]
    for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
      let data = try PropertyListSerialization.data(
        fromPropertyList: applications, format: format, options: 0)
      try require(
        try SimulatorApplications.decodeBundleIDs(data) == expected,
        "Accept XML and binary property lists without depending on output formatting.")
    }
    try require(
      try SimulatorApplications.decodeBundleIDs(Data("{}".utf8)).isEmpty,
      "An empty dictionary is a successful empty inventory.")
  }

  static func rejectInvalidResponses() throws {
    let array = try PropertyListSerialization.data(
      fromPropertyList: ["com.example.First"], format: .xml, options: 0)
    for data in [
      Data([0x00, 0xFF]), Data("{".utf8), array,
      Data("{ \"com.example.First\" = scalar; }".utf8), Data("{ \"\" = {}; }".utf8),
    ] {
      do {
        _ = try SimulatorApplications.decodeBundleIDs(data)
      } catch { continue }
      throw failure(
        "Malformed, non-dictionary, and invalid app entries must not mean no installed apps.")
    }
  }

  @MainActor
  static func querySelectedDevice() async throws {
    let identifiers = try await SimulatorApplications.installedBundleIDs(on: device) {
      executable, arguments in
      try require(executable == "/usr/bin/xcrun", "Resolve the tool through the system xcrun.")
      try require(
        arguments == ["simctl", "listapps", device.id],
        "Query the exact selected UDID, without booted aliases or unsupported JSON flags.")
      try require(!Thread.isMainThread, "The synchronous tool must not block the main thread.")
      return listing
    }
    try require(
      identifiers == ["com.example.First", "com.apple.mobilesafari"],
      "Return installed identifiers from the selected simulator.")
  }

  static func preserveCommandFailure() async throws {
    let expected = failure("Simulator service is unavailable.")
    do {
      _ = try await SimulatorApplications.installedBundleIDs(on: device) { _, _ in throw expected }
    } catch {
      try require(
        (error as NSError) == expected,
        "A query failure must preserve its diagnostic rather than return an empty inventory.")
      return
    }
    throw failure("A failed installed-app query must throw.")
  }

  static func rejectStoppedDevices() async throws {
    for state in ["Shutdown", "Booting", "Shutting Down"] {
      let stopped = SimulatorDevice(
        id: device.id, name: device.name, runtime: device.runtime, state: state)
      do {
        _ = try await SimulatorApplications.installedBundleIDs(on: stopped) { _, _ in
          throw failure("A non-booted simulator must not invoke a live app query.")
        }
      } catch SimulatorApplicationsError.notRunning {
        continue
      }
      throw failure("A non-booted simulator must have an unknown inventory.")
    }
  }

  static func cancelledBeforeQuery() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await SimulatorApplications.installedBundleIDs(on: device) { _, _ in
        throw failure("An already cancelled query must not invoke simctl.")
      }
    }
    do {
      _ = try await task.value
    } catch is CancellationError {
      return
    }
    throw failure("An already cancelled query must throw CancellationError.")
  }

  static func cancelledDuringQuery() async throws {
    let started = DispatchSemaphore(value: 0)
    let finish = DispatchSemaphore(value: 0)
    let task = Task {
      try await SimulatorApplications.installedBundleIDs(on: device) { _, _ in
        started.signal()
        try require(
          finish.wait(timeout: .now() + 5) == .success,
          "The test must release the in-flight app query.")
        return listing
      }
    }
    let didStart = await Task.detached { waitForQuery(started) }.value
    task.cancel()
    finish.signal()
    try require(didStart, "The app query must start before testing in-flight cancellation.")
    do {
      _ = try await task.value
    } catch is CancellationError {
      return
    }
    throw failure("Cancellation during an app query must not publish its inventory.")
  }

  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw failure(message) }
  }

  static func waitForQuery(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now() + 5) == .success
  }

  static func failure(_ message: String) -> NSError {
    NSError(
      domain: "SimulatorApplicationsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
