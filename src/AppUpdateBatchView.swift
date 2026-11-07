import SwiftUI

struct AppUpdateAllButton: View {
  let isUpdating: Bool
  let canUpdate: Bool
  let action: () -> Void

  var body: some View {
    Group {
      if isUpdating {
        button.buttonStyle(.bordered)
      } else {
        button.buttonStyle(.borderedProminent)
      }
    }
    .accessibilityIdentifier("update-all")
  }

  private var button: some View {
    Button(action: action) {
      StableSizeView(isUpdating, states: [false, true]) { updating in
        if updating { Text("Updating…") } else { Text("Update All") }
      }
    }
    .disabled(isUpdating || !canUpdate)
  }
}

struct AppUpdateBatchView: View {
  let batch: AppUpdateBatch
  let phase: AppInstallationPhase?
  let cancel: () -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        heading.fontWeight(.medium)
        Spacer(minLength: 0)
        if batch.isRunning {
          Text(verbatim: "\(batch.completed) / \(batch.total)").monospacedDigit()
            .foregroundStyle(.secondary)
          Button("Cancel All", action: cancel).disabled(batch.isStopping)
        } else {
          Button("Dismiss", action: dismiss)
        }
      }
      if batch.isRunning {
        ProgressView(value: Double(batch.completed), total: Double(batch.total))
          .accessibilityLabel(Text(progressTitle))
        if let app = batch.currentApp {
          HStack(spacing: 12) {
            Text(verbatim: app.name).lineLimit(1)
            Spacer(minLength: 0)
            if let phase { Text(verbatim: phase.title) }
          }
          .foregroundStyle(.secondary)
        }
      } else {
        Text("\(batch.updated) updated, \(batch.failed) failed, \(batch.canceled) canceled")
          .foregroundStyle(.secondary)
        if batch.failed > 0 {
          DisclosureGroup("Failed Updates") {
            ScrollView {
              VStack(alignment: .leading, spacing: 10) {
                ForEach(batch.failures, id: \.app.id) { failure in
                  VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: failure.app.name).fontWeight(.medium)
                    Text(verbatim: failure.message).foregroundStyle(.secondary)
                      .textSelection(.enabled)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .padding(.top, 8)
            }
            .frame(maxHeight: 160)
          }
          .disclosureGroupStyle(DetailsDisclosureStyle())
        }
      }
    }
    .font(.system(size: 12))
    .padding(12)
    .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityIdentifier("update-batch")
  }

  private var progressTitle: LocalizedStringKey {
    batch.isStopping ? "Stopping Updates…" : "Updating Apps"
  }

  @ViewBuilder
  private var heading: some View {
    if batch.isRunning {
      Text(progressTitle)
    } else if batch.failed > 0 {
      Label("Some Updates Failed", systemImage: "exclamationmark.triangle")
        .foregroundStyle(.orange)
    } else if batch.canceled > 0 {
      Text("Updates Canceled")
    } else {
      Label("Updates Complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    }
  }
}
