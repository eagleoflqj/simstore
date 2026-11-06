import SwiftUI

@MainActor
struct SelfUpdateView: View {
  let store: SelfUpdateStore
  var close: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable().frame(width: 72, height: 72)
        .accessibilityHidden(true)
      Text(verbatim: "SimStore").font(.title.bold())
      if let current = store.current {
        VStack(spacing: 5) {
          Text(verbatim: current.displayVersion).font(.headline)
          Link(
            destination: AppConfiguration.commitURL(
              repository: AppConfiguration.repositoryURL, revision: current.revision)
          ) {
            Text(verbatim: current.description).font(.caption.monospaced())
          }
          Text(Date(timeIntervalSince1970: TimeInterval(current.time)), style: .date)
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Divider()
      status.frame(maxWidth: .infinity, minHeight: 116)
      HStack(spacing: 12) {
        if let phase = store.phase {
          Button("Cancel", action: store.cancel)
            .disabled(!phase.canCancel)
            .keyboardShortcut(.cancelAction)
        } else {
          Button("Done", action: close).keyboardShortcut(.cancelAction)
          Spacer(minLength: 0)
          if let release = store.release {
            if release.isNightly {
              Button("Install Nightly and Restart", action: store.install)
            } else {
              Button("Update and Restart", action: store.install).buttonStyle(.borderedProminent)
            }
          } else {
            Button(action: store.check) {
              StableSizeView(store.isChecking, states: [false, true]) { checking in
                if checking { Text("Checking…") } else { Text("Check for Updates") }
              }
            }
            .disabled(store.isChecking)
          }
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
    }
    .padding(24)
    .frame(width: 460)
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private var status: some View {
    if let error = store.error {
      VStack(spacing: 8) {
        Label("Couldn’t Update SimStore", systemImage: "exclamationmark.triangle")
          .font(.headline)
        Text(verbatim: error).foregroundStyle(.secondary).textSelection(.enabled)
      }
      .multilineTextAlignment(.center)
    } else if let phase = store.phase, let release = store.release {
      VStack(spacing: 12) {
        if case .downloading(let bytes) = phase {
          DownloadProgressView(
            receivedBytes: bytes, totalBytes: release.size, title: phase.title)
        } else {
          ProgressView().controlSize(.small)
          if phase == .installing {
            Text("Restarting SimStore…")
          } else {
            Text(verbatim: phase.title)
          }
        }
        Text("SimStore will quit and reopen to finish the update.")
          .font(.caption).foregroundStyle(.secondary)
      }
    } else if let release = store.release {
      VStack(spacing: 8) {
        if release.isNightly {
          Label("A New Nightly Is Available", systemImage: "moon.stars")
            .font(.headline)
          Text("Nightly builds are unstable and may contain bugs.")
            .foregroundStyle(.secondary)
        } else {
          Text("A New Version Is Available").font(.headline)
        }
        Link(
          destination: AppConfiguration.repositoryURL.appending(path: "releases/tag")
            .appending(component: release.tag)
        ) {
          Text(verbatim: release.displayVersion)
        }
        Text(verbatim: ByteCountFormatter.string(fromByteCount: release.size, countStyle: .file))
          .font(.caption).foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
    } else if store.hasChecked && !store.isChecking {
      VStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
        Text("SimStore Is Up to Date").font(.headline)
        Text("You’re using the latest version available for macOS \(store.os).")
          .font(.callout).foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
    } else {
      Text("Get the latest SimStore version compatible with this Mac.")
        .foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
  }
}
