import AppKit
import SwiftUI

struct CopyableText: View {
  let value: String
  let copyLabel: LocalizedStringKey

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(verbatim: value).textSelection(.enabled)
      Button {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
      } label: {
        Label(copyLabel, systemImage: "doc.on.doc")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .controlSize(.small)
      .help(Text(copyLabel))
    }
  }
}
