import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class SidebarState {
  var discovery: SimulatorDiscovery?
  var selectedDeviceID: String?
  var section = LibrarySection.discover
}

private struct SidebarHarness: View {
  @Bindable var state: SidebarState

  var body: some View {
    GeometryReader { geometry in
      SidebarView(
        discovery: state.discovery, isChecking: false, needsXcode: false,
        section: $state.section, updateCount: nil, selectedDeviceID: state.selectedDeviceID,
        selectDevice: { state.selectedDeviceID = $0 }, openRepository: {}
      )
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }
  }
}

@main
@MainActor
struct SidebarSelectionTests {
  static func main() async {
    do {
      NSApplication.shared.setActivationPolicy(.regular)
      let devices: [SimulatorDevice]
      if CommandLine.arguments.count == 2 {
        devices = try SimulatorDiscovery.decodeDevices(
          Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
      } else {
        devices = (0..<20).map {
          SimulatorDevice(
            id: "device-\($0)", name: "iPhone \($0)", runtime: "27.0",
            state: $0 == 12 ? "Booted" : "Shutdown")
        }
      }
      guard let selected = devices.firstIndex(where: { $0.state == "Booted" }) else {
        throw failure("The inventory needs an already booted iPhone.")
      }
      let state = SidebarState()
      let host = NSHostingView(rootView: SidebarHarness(state: state))
      let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 240, height: 730),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      window.makeKeyAndOrderFront(nil)
      defer { window.close() }
      try await Task.sleep(for: .milliseconds(100))
      state.discovery = discovery(devices)
      state.selectedDeviceID = devices[selected].id
      try await settle(host)
      guard let table = tables(in: host).first(where: { $0.numberOfRows == devices.count }),
        let scroll = table.enclosingScrollView
      else { throw failure("Expected the native simulator list.") }
      try requireVisible(selected, in: table)
      print(
        "Selected \(devices[selected].name): row=\(table.rect(ofRow: selected)), visible=\(table.visibleRect)"
      )

      for index in [devices.count - 1, 0, selected] {
        state.selectedDeviceID = devices[index].id
        try await settle(host)
        try requireVisible(index, in: table)
      }

      scroll.contentView.scroll(to: .zero)
      scroll.reflectScrolledClipView(scroll.contentView)
      let offset = table.visibleRect.origin
      state.discovery = discovery(devices)
      try await settle(host)
      guard table.visibleRect.origin == offset else {
        throw failure("Refreshing the same selection must preserve manual scrolling.")
      }

      // A recreated sidebar must also reveal a selection that predates its appearance.
      let recreated = NSHostingView(rootView: SidebarHarness(state: state))
      window.contentView = recreated
      try await settle(recreated)
      guard let restored = tables(in: recreated).first(where: { $0.numberOfRows == devices.count })
      else { throw failure("Expected the recreated simulator list.") }
      try requireVisible(selected, in: restored)
      print(
        "PASS: initial selection, programmatic selection, sidebar recreation, and manual scroll preservation."
      )
    } catch {
      FileHandle.standardError.write(
        Data("Sidebar selection test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  private static func settle(_ view: NSView) async throws {
    for _ in 0..<20 {
      view.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private static func tables(in view: NSView) -> [NSTableView] {
    (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables(in: $0) }
  }

  private static func discovery(_ devices: [SimulatorDevice]) -> SimulatorDiscovery {
    SimulatorDiscovery(developerDirectory: URL(fileURLWithPath: "/Developer"), devices: devices)
  }

  private static func requireVisible(_ index: Int, in table: NSTableView) throws {
    guard table.selectedRow == index, table.visibleRect.contains(table.rect(ofRow: index)) else {
      throw failure("Selected row \(index) must be fully visible: \(table.visibleRect).")
    }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(
      domain: "SidebarSelectionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
