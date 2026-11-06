import Foundation

@main
struct SelfUpdateTests {
  @MainActor
  static func main() async {
    do {
      try SelfUpdateModelTests.run()
      try SelfUpdatePackageTests.run()
      try await SelfUpdateInstallerTests.run()
      try await SelfUpdateStoreTests.run()
      try await SelfUpdateViewTests.run()
    } catch {
      FileHandle.standardError.write(
        Data("Self-update test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }
}
