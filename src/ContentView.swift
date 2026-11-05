import AppKit
import SwiftUI

@MainActor
struct ContentView: View {
  @State private var simulators: SimulatorStore
  @State private var catalog: CatalogStore
  @State private var installedApps: InstalledAppsStore
  @State private var installations: AppInstallationStore
  @State private var launchError: String?

  private static var installedXcodeURL: URL? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode")
  }

  init(
    discover: @escaping @MainActor () async throws -> SimulatorDiscovery = {
      #if DEBUG
        if let scenario = try PreviewScenario.parse(CommandLine.arguments) {
          return try await scenario.discover(installedXcodeURL: ContentView.installedXcodeURL)
        }
      #endif
      return try await SimulatorDiscovery.scan(installedXcodeURL: ContentView.installedXcodeURL)
    },
    boot: @escaping @Sendable (String) async throws -> Void = {
      try await SimulatorControl.boot($0)
    },
    catalogClient: CatalogClient = .live,
    installer: AppInstaller = AppInstaller(),
    loadInstalledApps: @escaping @Sendable (SimulatorDevice) async throws -> Set<String> = {
      try await SimulatorApplications.installedBundleIDs(on: $0)
    }
  ) {
    _simulators = State(initialValue: SimulatorStore(discover: discover, boot: boot))
    _catalog = State(initialValue: CatalogStore(client: catalogClient))
    let installedApps = InstalledAppsStore(load: loadInstalledApps)
    _installedApps = State(initialValue: installedApps)
    _installations = State(
      initialValue: AppInstallationStore(
        installer: installer,
        didInstall: { bundleID, deviceID in
          installedApps.recordInstallation(bundleID: bundleID, deviceID: deviceID)
        }))
  }

  private var needsXcode: Bool {
    guard case .failure(let error) = simulators.result else { return false }
    return (error as? SimulatorDiscoveryError) == .xcodeNotInstalled
  }

  private var discovery: SimulatorDiscovery? {
    simulators.discovery
  }

  private var deviceManager: (name: String, url: URL)? {
    discovery?.deviceManager
  }

  var body: some View {
    NavigationSplitView {
      GeometryReader { geometry in
        SidebarView(
          discovery: discovery, isChecking: simulators.isChecking, needsXcode: needsXcode,
          selectedDeviceID: simulators.selectedDeviceID,
          startingDeviceIDs: simulators.startingDeviceIDs, selectDevice: simulators.selectDevice,
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

          if simulators.selectedDevice == nil || discovery == nil {
            DiscoverHeading()
              .padding(32)
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .background(Color(nsColor: .textBackgroundColor))
      }
      .toolbar {
        ToolbarItem(placement: .navigation) {
          SimulatorPicker(
            devices: discovery?.devices ?? [], selectedDevice: simulators.selectedDevice,
            selectDevice: simulators.selectDevice
          )
          .labelStyle(.titleAndIcon)
          .font(.system(size: 12))
        }
        ToolbarItem(placement: .primaryAction) {
          Button(action: checkAgain) {
            Label("Check for Simulators", systemImage: "arrow.clockwise")
          }
          .disabled(simulators.isChecking)
          .keyboardShortcut("r", modifiers: .command)
          .help(Text("Check for iOS simulators"))
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 900, minHeight: 600)
    .task { await simulators.refresh() }
    .task(id: shouldMonitorState) {
      while shouldMonitorState && !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(2))
          try Task.checkCancellation()
          await simulators.refresh()
        } catch { return }
      }
    }
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
    .alert(
      "Couldn’t Start Simulator",
      isPresented: Binding(
        get: { simulators.startError != nil },
        set: { if !$0 { simulators.startError = nil } }
      )
    ) {
      Button("OK", role: .cancel) { simulators.startError = nil }
    } message: {
      Text(simulators.startError ?? "")
    }
  }

  @ViewBuilder
  private var discoveryContent: some View {
    switch simulators.result {
    case .none:
      SimulatorLoadingView()
    case .some(.success(let snapshot)) where snapshot.devices.isEmpty:
      NoSimulatorsView(
        deviceManagerName: deviceManager?.name, isChecking: simulators.isChecking,
        openDeviceManager: openDeviceManager, openXcode: openXcode, checkAgain: checkAgain)
    case .some(.success):
      if let device = simulators.selectedDevice {
        CatalogBrowserView(
          store: catalog, installedApps: installedApps, installations: installations,
          device: device,
          isStarting: simulators.isStartingSelectedDevice,
          deviceManagerName: deviceManager?.name,
          startSimulator: startSimulator,
          openDeviceManager: openDeviceManager)
      }
    case .some(.failure) where needsXcode:
      MissingXcodeView(
        isChecking: simulators.isChecking, openAppStore: openAppStore, checkAgain: checkAgain)
    case .some(.failure(let error)):
      SimulatorDiscoveryErrorView(
        error: error, isChecking: simulators.isChecking, openXcode: openXcode,
        checkAgain: checkAgain)
    }
  }

  private func checkAgain() {
    Task {
      await simulators.refresh()
      if let device = simulators.selectedDevice { await installedApps.refresh(for: device) }
    }
  }

  private func startSimulator() {
    let id = simulators.selectedDeviceID
    Task {
      let started = await simulators.startSelectedDevice()
      if started, let device = simulators.selectedDevice, device.id == id {
        openDeviceManager()
      }
    }
  }

  private var shouldMonitorState: Bool {
    !simulators.startingDeviceIDs.isEmpty
      || discovery?.devices.contains(where: \.isTransitioning) == true
  }

  private func openRepository() {
    let url = AppConfiguration.buildsRepositoryURL
    if !NSWorkspace.shared.open(url) {
      launchError = String(localized: "Open \(url.absoluteString) in your web browser.")
    }
  }

  private func openAppStore() {
    if !NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!) {
      launchError = String(localized: "Open the App Store and search for Xcode.")
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
    openApplication(discovery?.xcodeURL ?? Self.installedXcodeURL, name: "Xcode")
  }

  private func openApplication(_ url: URL?, name: String) {
    guard let url, FileManager.default.fileExists(atPath: url.path) else {
      launchError = String(
        localized:
          "\(name) couldn’t be opened. Make sure the full Xcode application is installed and selected."
      )
      return
    }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) {
      _, error in
      if let error {
        Task { @MainActor in
          launchError = String(
            localized: "\(name) couldn’t be opened. \(error.localizedDescription)")
        }
      }
    }
  }
}
