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
        sidebar
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
          Button {
            Task { await refresh() }
          } label: {
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
      Task { await refresh() }
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

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 37, height: 37)
        Text("SimStore")
          .font(.system(size: 22, weight: .bold))
          .tracking(-0.7)
      }
      .padding(.horizontal, 20)
      .padding(.top, 24)
      .padding(.bottom, 27)
      .fixedSize(horizontal: false, vertical: true)

      VStack(spacing: 5) {
        Label("Discover", systemImage: "safari")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.accentColor)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 11)
          .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
          .accessibilityAddTraits(.isSelected)
        sidebarPlaceholder("Installed", systemImage: "square.grid.2x2")
        sidebarPlaceholder("Updates", systemImage: "arrow.triangle.2.circlepath")
      }
      .padding(.horizontal, 12)
      .fixedSize(horizontal: false, vertical: true)

      Text("SIMULATORS")
        .font(.system(size: 10, weight: .semibold))
        .tracking(1)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 15)
        .fixedSize(horizontal: false, vertical: true)

      if let discovery, !discovery.devices.isEmpty {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(discovery.devices) { device in
              Label {
                VStack(alignment: .leading, spacing: 4) {
                  Text(device.name).font(.system(size: 12, weight: .medium))
                  Text("iOS \(device.runtime) · \(device.state)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
              } icon: {
                Image(systemName: device.name.contains("iPad") ? "ipad.landscape" : "iphone")
                  .foregroundStyle(.secondary)
              }
            }
          }
          .padding(.horizontal, 24)
          .padding(.vertical, 4)
        }
        .frame(minHeight: 0)
      } else {
        VStack(alignment: .leading, spacing: 7) {
          Text(
            isChecking
              ? "Checking for devices…"
              : needsXcode
                ? "Xcode required"
                : discovery == nil ? "No devices to display" : "No simulators yet"
          )
          .font(.system(size: 12, weight: .medium))
          Text(
            needsXcode
              ? "Install Xcode to add iPhone and iPad simulators."
              : "Your iPhone and iPad simulators will appear here."
          )
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
      }

      Spacer(minLength: 24)

      Button {
        if !NSWorkspace.shared.open(URL(string: "https://github.com/eagleoflqj/simstore-builds")!) {
          launchError = "Open https://github.com/eagleoflqj/simstore-builds in your web browser."
        }
      } label: {
        Label("App Repository", systemImage: "arrow.up.right.square")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .padding(24)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func sidebarPlaceholder(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .font(.system(size: 13))
      .foregroundStyle(.tertiary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
  }

  @ViewBuilder
  private var discoveryContent: some View {
    switch result {
    case .none:
      VStack(spacing: 15) {
        ProgressView().controlSize(.small)
        Text("Looking for your simulators…")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
    case .some(.success(let snapshot)) where snapshot.devices.isEmpty:
      emptyState
    case .some(.success(let snapshot)):
      VStack(spacing: 14) {
        Image(systemName: "iphone.and.arrow.forward")
          .font(.system(size: 48, weight: .light))
          .foregroundStyle(Color.accentColor)
        Text("Your simulators are ready")
          .font(.system(size: 24, weight: .semibold))
        Text(
          "Found \(snapshot.devices.count) available iOS \(snapshot.devices.count == 1 ? "simulator" : "simulators")."
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      }
    case .some(.failure) where needsXcode:
      missingXcodeState
    case .some(.failure(let error)):
      VStack(spacing: 16) {
        Image(systemName: "exclamationmark.triangle")
          .font(.system(size: 44, weight: .light))
          .foregroundStyle(.orange)
        Text("Couldn’t check for simulators")
          .font(.system(size: 24, weight: .semibold))
        Text(
          "Make sure Xcode is installed and its command-line tools are selected, then try again."
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 390)
        HStack(spacing: 10) {
          Button("Open Xcode", systemImage: "hammer") { openXcode() }
          Button(isChecking ? "Checking…" : "Try Again", systemImage: "arrow.clockwise") {
            Task { await refresh() }
          }
          .disabled(isChecking)
        }
        .controlSize(.large)
        DisclosureGroup("Details") {
          Text(error.localizedDescription)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .font(.system(size: 11))
        .frame(maxWidth: 390)
      }
      .padding(30)
    }
  }

  private var missingXcodeState: some View {
    VStack(spacing: 0) {
      Image(systemName: "hammer")
        .font(.system(size: 58, weight: .light))
        .foregroundStyle(Color.accentColor)
        .frame(width: 130, height: 130)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 30))
        .padding(.bottom, 30)
      Text("Start with Xcode.")
        .font(.system(size: 25, weight: .semibold))
        .tracking(-0.6)
      Text(
        "Xcode provides the tools SimStore needs to run iOS apps.\nInstall it from the App Store, then open it to finish setup."
      )
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .lineSpacing(5)
      .padding(.top, 12)
      HStack(spacing: 10) {
        Button("Open App Store", systemImage: "bag") {
          if !NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!)
          {
            launchError = "Open the App Store and search for Xcode."
          }
        }
        .buttonStyle(.borderedProminent)
        Button(isChecking ? "Checking…" : "Check Again", systemImage: "arrow.clockwise") {
          Task { await refresh() }
        }
        .buttonStyle(.bordered)
        .disabled(isChecking)
      }
      .controlSize(.large)
      .padding(.top, 25)
    }
    .padding(.horizontal, 30)
  }

  private var emptyState: some View {
    VStack(spacing: 0) {
      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0)],
              center: .center, startRadius: 35, endRadius: 125)
          )
          .frame(width: 250, height: 200)
        Image(systemName: "ipad.landscape")
          .font(.system(size: 78, weight: .ultraLight))
          .foregroundStyle(Color.secondary.opacity(0.25))
          .rotationEffect(.degrees(-9))
          .offset(x: -35, y: 12)
        Image(systemName: "iphone.gen3")
          .font(.system(size: 112, weight: .ultraLight))
          .foregroundStyle(Color.accentColor.opacity(0.85))
          .rotationEffect(.degrees(9))
          .offset(x: 36, y: -6)
      }
      .accessibilityHidden(true)

      Text("A simulator is where it starts.")
        .font(.system(size: 25, weight: .semibold))
        .tracking(-0.6)
        .padding(.top, 6)
      Text(
        "Create an iPhone or iPad simulator in \(deviceManager?.name ?? "Xcode").\nThen come back to find your next favorite app."
      )
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .lineSpacing(5)
      .padding(.top, 12)

      HStack(spacing: 10) {
        Button(
          "Open \(deviceManager?.name ?? "Xcode")",
          systemImage: deviceManager?.name == nil ? "hammer" : "iphone.and.arrow.forward"
        ) {
          if let deviceManager {
            openApplication(deviceManager.url, name: deviceManager.name)
          } else {
            openXcode()
          }
        }
        .buttonStyle(.borderedProminent)
        Button(isChecking ? "Checking…" : "Check Again", systemImage: "arrow.clockwise") {
          Task { await refresh() }
        }
        .buttonStyle(.bordered)
        .disabled(isChecking)
      }
      .controlSize(.large)
      .padding(.top, 25)

      if deviceManager?.name != nil {
        Button {
          openXcode()
        } label: {
          HStack(spacing: 5) {
            Text("Open Xcode")
            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
          }
          .font(.system(size: 11))
        }
        .buttonStyle(.link)
        .padding(.top, 18)
      } else {
        Text("Device Hub or Simulator couldn’t be found in the selected Xcode installation.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .padding(.top, 18)
      }
    }
    .padding(.horizontal, 30)
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
