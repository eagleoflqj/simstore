import AppKit
import SwiftUI

@MainActor
struct ContentView: View {
  private let discover: @MainActor () async throws -> SimulatorDiscovery
  @State private var result: Result<SimulatorDiscovery, Error>?
  @State private var isChecking = false
  @State private var launchError: String?

  init(
    discover: @escaping @MainActor () async throws -> SimulatorDiscovery = {
      try await SimulatorDiscovery.scan(
        installedXcodeURL: NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: "com.apple.dt.Xcode"))
    }
  ) {
    self.discover = discover
  }

  private var needsXcode: Bool {
    guard case .failure(let error) = result else { return false }
    return (error as? SimulatorDiscoveryError) == .xcodeNotInstalled
  }

  private var discovery: SimulatorDiscovery? {
    guard case .success(let value) = result else { return nil }
    return value
  }

  private var deviceManager: (name: String, url: URL)? {
    discovery?.deviceManager
  }

  var body: some View {
    NavigationSplitView {
      GeometryReader { geometry in
        SidebarView(
          discovery: discovery, isChecking: isChecking, needsXcode: needsXcode,
          openRepository: openRepository
        )
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
      }
      .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    } detail: {
      GeometryReader { geometry in
        ZStack(alignment: .topLeading) {
          discoveryContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          VStack(alignment: .leading, spacing: 7) {
            Text("Discover")
              .font(.system(size: 30, weight: .bold))
              .tracking(-0.8)
            Text("Open-source favorites. Built for your simulator.")
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
          }
          .padding(32)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .background(Color(nsColor: .textBackgroundColor))
      }
      .toolbar {
        ToolbarItem(placement: .navigation) {
          Label("No simulator selected", systemImage: "iphone")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .fixedSize()
        }
        ToolbarItem(placement: .primaryAction) {
          Button(action: checkAgain) {
            Label("Check for Simulators", systemImage: "arrow.clockwise")
          }
          .disabled(isChecking)
          .keyboardShortcut("r", modifiers: .command)
          .help("Check for iOS simulators")
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 900, minHeight: 600)
    .task { await refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      checkAgain()
    }
    .alert(
      "Couldn’t Open Application",
      isPresented: Binding(
        get: { launchError != nil },
        set: { if !$0 { launchError = nil } }
      )
    ) {
      Button("OK", role: .cancel) { launchError = nil }
    } message: {
      Text(launchError ?? "")
    }
  }

  @ViewBuilder
  private var discoveryContent: some View {
    switch result {
    case .none:
      SimulatorLoadingView()
    case .some(.success(let snapshot)) where snapshot.devices.isEmpty:
      NoSimulatorsView(
        deviceManagerName: deviceManager?.name, isChecking: isChecking,
        openDeviceManager: openDeviceManager, openXcode: openXcode, checkAgain: checkAgain)
    case .some(.success(let snapshot)):
      SimulatorsReadyView(count: snapshot.devices.count)
    case .some(.failure) where needsXcode:
      MissingXcodeView(
        isChecking: isChecking, openAppStore: openAppStore, checkAgain: checkAgain)
    case .some(.failure(let error)):
      SimulatorDiscoveryErrorView(
        error: error, isChecking: isChecking, openXcode: openXcode, checkAgain: checkAgain)
    }
  }

  private func checkAgain() {
    Task { await refresh() }
  }

  private func refresh() async {
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }
    do {
      let snapshot = try await discover()
      try Task.checkCancellation()
      result = .success(snapshot)
    } catch is CancellationError {
      return
    } catch {
      result = .failure(error)
    }
  }

  private func openRepository() {
    let url = AppConfiguration.buildsRepositoryURL
    if !NSWorkspace.shared.open(url) {
      launchError = "Open \(url.absoluteString) in your web browser."
    }
  }

  private func openAppStore() {
    if !NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!) {
      launchError = "Open the App Store and search for Xcode."
    }
  }

  private func openDeviceManager() {
    if let deviceManager {
      openApplication(deviceManager.url, name: deviceManager.name)
    } else {
      openXcode()
    }
  }

  private func openXcode() {
    openApplication(
      discovery?.xcodeURL
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode"),
      name: "Xcode")
  }

  private func openApplication(_ url: URL?, name: String) {
    guard let url, FileManager.default.fileExists(atPath: url.path) else {
      launchError =
        "\(name) couldn’t be opened. Make sure the full Xcode application is installed and selected."
      return
    }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) {
      _, error in
      if let error {
        Task { @MainActor in
          launchError = "\(name) couldn’t be opened. \(error.localizedDescription)"
        }
      }
    }
  }
}
