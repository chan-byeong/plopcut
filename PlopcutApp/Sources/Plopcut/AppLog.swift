import AppKit
import PlopcutCore

/// The app's one support log (STA-80): `~/Library/Logs/plopcut/plopcut.log`, local only, never uploaded.
enum AppLog {
    /// Only the packaged app writes the real log. `swift test`, `swift run` and any other host process get a no-op,
    /// so tests can never touch the user's log, whatever test framework or environment they run under.
    static let shared: EventLogging = isPackagedApp ? FileEventLog() : NullEventLog()

    private static var isPackagedApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app") && Bundle.main.bundleIdentifier != nil
    }

    /// Moves the folders used under the former name Notedrop (STA-85). Runs before anything opens the settings or the
    /// log, and only in the packaged app, so tests and `swift run` never move a developer's real folders. A failed
    /// step is logged by code and the app keeps using the paths that are left.
    static func migrateLegacyFolders(
        _ migration: LegacyMigration? = isPackagedApp ? LegacyMigration() : nil, log: EventLogging = shared
    ) {
        for error in migration?.run() ?? [] { log.log(error: error) }
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
