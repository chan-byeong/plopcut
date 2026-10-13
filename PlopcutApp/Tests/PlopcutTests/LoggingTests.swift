import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

final class LogRecorder: EventLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [LogEvent] = []
    var events: [LogEvent] { lock.withLock { stored } }
    func log(_ event: LogEvent) { lock.withLock { stored.append(event) } }
}

private final class MutableChecker: PermissionChecking, @unchecked Sendable {
    var accessibility = false
    func accessibilityTrusted() -> Bool { accessibility }
    func clipboardReadable() -> Bool? { true }
}

@MainActor
@Suite struct LoggingTests {
    // STA-80: only status changes are logged, by item and status name.
    @Test func permissionChangesAreLoggedOnce() {
        let checker = MutableChecker()
        let recorder = LogRecorder()
        let model = PermissionsModel(checker: checker, openURL: { _ in }, log: recorder)
        model.refresh()
        #expect(recorder.events.isEmpty)
        checker.accessibility = true
        model.refresh()
        model.refresh()
        #expect(recorder.events == [.permission(item: "accessibility", status: "granted")])
    }

    // STA-85: a migration problem is logged by error code after the move, never as a path.
    @Test func legacyMigrationErrorsAreLoggedByCode() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("plopcut-migrate-\(UUID().uuidString)")
        let legacySupport = home.appendingPathComponent("Library/Application Support/Notedrop", isDirectory: true)
        try FileManager.default.createDirectory(at: legacySupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Documents/Notedrop"), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: legacySupport.appendingPathComponent("settings.json"))
        let recorder = LogRecorder()

        AppLog.migrateLegacyFolders(LegacyMigration(home: home), log: recorder)

        #expect(recorder.events == [.error(code: "settings_invalid")])
    }

    @Test func legacyMigrationIsSkippedOutsideThePackagedApp() {
        let recorder = LogRecorder()
        AppLog.migrateLegacyFolders(log: recorder)  // swift test is not a packaged app, so nothing runs
        #expect(recorder.events.isEmpty)
    }

    @Test func appStartLogsVersionBuildAndMacOSOnly() {
        let recorder = LogRecorder()
        AppLog.logStart(info: ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "45"], log: recorder)
        guard case let .appStart(version, build, macOS)? = recorder.events.first else {
            Issue.record("no app_start event")
            return
        }
        #expect(version == "1.2.0" && build == "45")
        #expect(macOS.split(separator: ".").count == 3)
    }

    @Test func showLogRowHasBothLanguages() {
        let entry = StringTable.entries["showLogInFinder"]
        #expect(entry?.en == "Show Log in Finder" && entry?.ko == "Finder에서 로그 보기")
    }

    @Test func testsNeverWriteToTheRealLog() {
        #expect(AppLog.shared is NullEventLog)
    }
}
