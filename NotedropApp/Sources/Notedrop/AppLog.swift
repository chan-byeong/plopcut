import AppKit
import NotedropCore

/// The app's one support log (STA-80): `~/Library/Logs/Notedrop/notedrop.log`, local only, never uploaded.
enum AppLog {
    /// Unit tests run inside the app's code and must not write to the user's real log.
    static let shared: EventLogging = isRunningTests ? NullEventLog() : FileEventLog()

    private static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil || Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
    }

    /// First line of a session: version, build and macOS version, nothing about the user.
    static func logStart(info: [String: Any] = Bundle.main.infoDictionary ?? [:], log: EventLogging = shared) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        log.log(.appStart(
            version: (info["CFBundleShortVersionString"] as? String) ?? "dev",
            build: (info["CFBundleVersion"] as? String) ?? "dev",
            macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"))
    }

    /// Selects the log file in Finder; if nothing has been logged yet, opens its folder.
    @MainActor
    static func revealInFinder(url: URL = FileEventLog.defaultURL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let folder = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }
}
