import Foundation
import NotedropCore
import Testing
@testable import Notedrop

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
