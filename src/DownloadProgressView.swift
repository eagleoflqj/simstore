import SwiftUI

struct DownloadProgressView: View {
  let receivedBytes: Int64
  let totalBytes: Int64
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ProgressView(
        value: Double(max(0, min(receivedBytes, totalBytes))), total: Double(totalBytes)
      ) {
        Text(verbatim: title)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(verbatim: ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file))
          .accessibilityIdentifier("download-received")
        Spacer(minLength: 8)
        Text(
          verbatim: "/ \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
        )
        .fixedSize()
        .accessibilityIdentifier("download-total")
      }
      .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
    }
  }
}
