import Foundation

@main
struct LocalizationTests {
  static func main() {
    do {
      try verifyTranslations()
      print("PASS: English and Simplified Chinese resources, simulator actions, and interpolation.")
    } catch {
      FileHandle.standardError.write(
        Data("Localization test failed: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  static func verifyTranslations() throws {
    guard CommandLine.arguments.count == 2,
      let app = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    else { throw failure("Expected the built App Bundle path.") }
    try require(Set(app.localizations) == ["en", "zh-Hans"], "Unexpected supported languages.")
    try require(app.developmentLocalization == "en", "English must be the fallback language.")

    for language in ["en", "zh-Hans"] {
      guard let directory = app.url(forResource: language, withExtension: "lproj"),
        let bundle = Bundle(url: directory)
      else { throw failure("Missing \(language) localization resources.") }
      for file in try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      where ["strings", "stringsdict"].contains(file.pathExtension) {
        _ = try String(contentsOf: file, encoding: .utf8)
      }
      let locale = Locale(identifier: language)
      let english = language == "en"
      let labels: [(String.LocalizationValue, String, String)] = [
        ("Discover", "Discover", "发现"), ("Installed", "Installed", "已安装"),
        ("Updates", "Updates", "更新"),
        ("Start Simulator", "Start Simulator", "启动模拟器"),
        ("Starting…", "Starting…", "正在启动…"),
        ("Booted", "Booted", "已启动"),
        ("Shutdown", "Shutdown", "已关机"),
        ("Booting", "Booting", "正在启动"),
        ("Shutting Down", "Shutting Down", "正在关机"),
      ]
      for (key, source, translated) in labels {
        try expect(
          String(localized: key, bundle: bundle, locale: locale), english ? source : translated)
      }

      let tool = "Device Hub"
      try expect(
        String(localized: "Open \(tool)", bundle: bundle, locale: locale),
        english ? "Open Device Hub" : "打开 Device Hub")
      let url = "https://example.com/releases/download/app%2F1.0.0/app.tar.bz2"
      try expect(
        String(localized: "Open \(url) in your web browser.", bundle: bundle, locale: locale),
        english ? "Open \(url) in your web browser." : "请在浏览器中打开 \(url)。")
      let detail = "Permission denied (13)."
      try expect(
        String(localized: "\(tool) couldn’t be opened. \(detail)", bundle: bundle, locale: locale),
        english ? "Device Hub couldn’t be opened. \(detail)" : "无法打开 Device Hub。\(detail)")
      let deviceName = "iPhone 测试"
      try expect(
        String(
          localized: "Couldn’t start \(deviceName).\n\(detail)", bundle: bundle, locale: locale),
        english ? "Couldn’t start \(deviceName).\n\(detail)" : "无法启动 \(deviceName)。\n\(detail)")
      try expect(
        String(
          localized:
            "Create an iPhone or iPad simulator in \(tool).\nThen come back to find your next favorite app.",
          bundle: bundle, locale: locale),
        english
          ? "Create an iPhone or iPad simulator in Device Hub.\nThen come back to find your next favorite app."
          : "在 Device Hub 中创建 iPhone 或 iPad 模拟器。\n然后回来发现你喜爱的应用。")

      let runtime = "27.0"
      try expect(
        String(localized: "iOS \(runtime)", bundle: bundle, locale: locale), "iOS 27.0")
    }
  }

  static func expect(_ actual: String, _ expected: String) throws {
    try require(actual == expected, "Expected '\(expected)', received '\(actual)'.")
  }

  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw failure(message) }
  }

  static func failure(_ message: String) -> NSError {
    NSError(domain: "LocalizationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
