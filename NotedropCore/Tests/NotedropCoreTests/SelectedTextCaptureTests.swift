import Foundation
import Testing
@testable import NotedropCore

/// Records every call in order so tests can assert sequencing (checklist P-01, P-16).
final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func add(_ entry: String) { lock.lock(); entries.append(entry); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return entries }
}

struct FakeReader: SelectedTextReader {
    let log: CallLog
    var value: String?
    func readSelection(in target: CaptureTarget?) -> String? {
        log.add("ax.read:\(target?.name ?? "none")")
        return value
    }
}

struct FakeCollector: SourceCollector {
    let log: CallLog
    var result = SourceResult(source: DropSource(appName: "Notes", windowTitle: "Ideas"), warnings: [])
    func collect(from target: CaptureTarget?) async -> SourceResult {
        log.add("source.collect:\(target?.name ?? "none")")
        return result
    }
}

struct FakeSender: CopyShortcutSender {
    let log: CallLog
    /// Runs when Cmd+C is "pressed"; lets a test mutate the fake clipboard like the frontmost app would.
    var onCopy: @Sendable () -> Void = {}
    var error: NotedropError?
    func sendCopy() throws {
        log.add("copy.send")
        if let error { throw error }
        onCopy()
    }
}

final class FakeClipboard: ClipboardAccess, @unchecked Sendable {
    private let lock = NSLock()
    private let log: CallLog
    private var snapshot: ClipboardSnapshot
    private var count: Int?
    /// Fails only the first read, which is the backup read.
    var failBackupRead: NotedropError?
    var writeError: NotedropError?
    /// Reads fail only after the first (backup) read when set.
    var failReadsAfterBackup: NotedropError?
    private var reads = 0

    init(log: CallLog, snapshot: ClipboardSnapshot = ClipboardSnapshot(text: "before", png: nil), changeCount: Int? = 1) {
        self.log = log
        self.snapshot = snapshot
        self.count = changeCount
    }

    var changeCount: Int? { lock.lock(); defer { lock.unlock() }; return count }

    var current: ClipboardSnapshot { lock.lock(); defer { lock.unlock() }; return snapshot }

    /// Simulates another app copying: new content and a bumped change count.
    func simulateCopy(_ text: String) {
        lock.lock(); snapshot = ClipboardSnapshot(text: text, png: nil); count = count.map { $0 + 1 }; lock.unlock()
    }

    func read() throws -> ClipboardSnapshot {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        log.add("clipboard.read")
        if reads == 1, let failBackupRead { throw failBackupRead }
        if reads > 1, let failReadsAfterBackup { throw failReadsAfterBackup }
        return snapshot
    }

    func write(_ newValue: ClipboardSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        log.add("clipboard.write")
        if let writeError { throw writeError }
        snapshot = newValue
        count = count.map { $0 + 1 }
    }
}

/// A sleep that never waits, counting polls instead.
final class PollCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var polls = 0
    func tick() { lock.lock(); polls += 1; lock.unlock() }
}

@Suite struct SelectedTextCaptureTests {
    private func makeCapture(
        log: CallLog, reader: String? = nil, clipboard: FakeClipboard, sender: FakeSender? = nil,
        collector: FakeCollector? = nil, counter: PollCounter = PollCounter(),
        frontmost: @escaping @Sendable () -> CaptureTarget? = { CaptureTarget(processID: 1, name: "Notes") }
    ) -> SelectedTextCapture {
        SelectedTextCapture(
            reader: FakeReader(log: log, value: reader),
            clipboard: clipboard,
            sender: sender ?? FakeSender(log: log),
            collector: collector ?? FakeCollector(log: log),
            frontmost: frontmost,
            sleep: { _ in counter.tick() })
    }

    // MARK: one pinned app (STA-50)

    @Test func frontmostAppIsResolvedOnceAndSharedByCollectorAndReader() async throws {
        let log = CallLog()
        let resolved = CallLog()
        // Every resolution would return a different app, as if focus moved during the capture.
        let capture = makeCapture(
            log: log, reader: "picked", clipboard: FakeClipboard(log: log),
            frontmost: {
                resolved.add("resolve")
                return CaptureTarget(processID: Int32(resolved.all.count), name: "App\(resolved.all.count)")
            })
        _ = try await capture.capture()
        #expect(resolved.all.count == 1)
        #expect(log.all == ["source.collect:App1", "ax.read:App1"])
    }

    @Test func noFrontmostAppStillReachesTheFallback() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log, snapshot: ClipboardSnapshot(text: "before", png: nil))
        let sender = FakeSender(log: log) { clipboard.simulateCopy("copied") }
        let capture = makeCapture(log: log, clipboard: clipboard, sender: sender, frontmost: { nil })
        let draft = try await capture.capture()
        #expect(draft.text == "copied")
        #expect(log.all.prefix(2) == ["source.collect:none", "ax.read:none"])
    }

    // MARK: accessibility path (P-16)

    @Test func accessibilityTextSkipsTheClipboardEntirely() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log)
        let capture = makeCapture(log: log, reader: "picked\r\n", clipboard: clipboard)
        let draft = try await capture.capture()
        #expect(draft.text == "picked")
        #expect(log.all == ["source.collect:Notes", "ax.read:Notes"])
        #expect(clipboard.current.text == "before")
    }

    @Test func sourceIsCollectedBeforeAnySelectionRead() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log)
        let sender = FakeSender(log: log) { clipboard.simulateCopy("copied") }
        let capture = makeCapture(log: log, reader: nil, clipboard: clipboard, sender: sender)
        _ = try await capture.capture()
        #expect(log.all.first == "source.collect:Notes")
        #expect(log.all.firstIndex(of: "ax.read:Notes")! < log.all.firstIndex(of: "clipboard.read")!)
    }

    // MARK: fallback trigger (P-17)

    @Test(arguments: [nil, "", "   \n\t"] as [String?])
    func missingOrBlankAccessibilityTextFallsBackToClipboard(_ ax: String?) async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log)
        let sender = FakeSender(log: log) { clipboard.simulateCopy("from clipboard") }
        let capture = makeCapture(log: log, reader: ax, clipboard: clipboard, sender: sender)
        let draft = try await capture.capture()
        #expect(draft.text == "from clipboard")
        #expect(log.all.contains("copy.send"))
    }

    // MARK: fallback behaviour (P-02..P-09)

    @Test func fallbackRestoresTheOriginalClipboardAfterSuccess() async throws {
        let log = CallLog()
        let original = ClipboardSnapshot(text: "original", png: Data([1, 2, 3]))
        let clipboard = FakeClipboard(log: log, snapshot: original)
        let sender = FakeSender(log: log) { clipboard.simulateCopy("copied") }
        let draft = try await makeCapture(log: log, clipboard: clipboard, sender: sender).capture()
        #expect(draft.text == "copied")
        #expect(clipboard.current == original)
        #expect(draft.warnings.isEmpty)
    }

    @Test func acceptsCopiedTextEqualToThePreviousClipboard() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log, snapshot: ClipboardSnapshot(text: "same", png: nil))
        let sender = FakeSender(log: log) { clipboard.simulateCopy("same") }
        let draft = try await makeCapture(log: log, clipboard: clipboard, sender: sender).capture()
        #expect(draft.text == "same")
    }

    // P-02: 25 ms between polls, 700 ms in total.
    @Test func pollingIsEveryTwentyFiveMillisecondsForSevenHundred() {
        #expect(SelectedTextCapture.pollInterval == .milliseconds(25))
        #expect(SelectedTextCapture.timeout == .milliseconds(700))
        #expect(SelectedTextCapture.maxPolls == 28)
        #expect(SelectedTextCapture.pollInterval * SelectedTextCapture.maxPolls == SelectedTextCapture.timeout)
    }

    @Test func timesOutAfterTwentyEightPollsAndRestores() async throws {
        let log = CallLog()
        let original = ClipboardSnapshot(text: "original", png: nil)
        let clipboard = FakeClipboard(log: log, snapshot: original)
        let counter = PollCounter()
        let capture = makeCapture(log: log, clipboard: clipboard, counter: counter)  // copy changes nothing
        await #expect(throws: NotedropError("no_selected_text")) { try await capture.capture() }
        #expect(counter.polls == 28)  // 700 ms / 25 ms
        #expect(clipboard.current == original)
    }

    @Test func blankClipboardAfterCopyIsNoSelectedTextAndRestores() async throws {
        let log = CallLog()
        let original = ClipboardSnapshot(text: "original", png: nil)
        let clipboard = FakeClipboard(log: log, snapshot: original)
        let sender = FakeSender(log: log) { clipboard.simulateCopy("  \n") }
        let capture = makeCapture(log: log, clipboard: clipboard, sender: sender)
        await #expect(throws: NotedropError("no_selected_text")) { try await capture.capture() }
        #expect(clipboard.current == original)
    }

    @Test func readFailureAfterCopyRestoresAndReportsClipboardUnavailable() async throws {
        let log = CallLog()
        let original = ClipboardSnapshot(text: "original", png: nil)
        let clipboard = FakeClipboard(log: log, snapshot: original)
        clipboard.failReadsAfterBackup = NotedropError("clipboard_unavailable")
        let sender = FakeSender(log: log) { clipboard.simulateCopy("copied") }
        let capture = makeCapture(log: log, clipboard: clipboard, sender: sender)
        await #expect(throws: NotedropError("clipboard_unavailable")) { try await capture.capture() }
        #expect(clipboard.current == original)
    }

    @Test func copyFailureRestoresTheClipboard() async throws {
        let log = CallLog()
        let original = ClipboardSnapshot(text: "original", png: nil)
        let clipboard = FakeClipboard(log: log, snapshot: original)
        let sender = FakeSender(log: log, error: NotedropError("boom"))
        let capture = makeCapture(log: log, clipboard: clipboard, sender: sender)
        await #expect(throws: NotedropError("boom")) { try await capture.capture() }
        #expect(clipboard.current == original)
    }

    // A capture that never copied anything must leave the clipboard alone: restoring would rewrite it as text+PNG
    // only and drop files, RTF or extra items.
    @Test func unchangedClipboardIsNotRewrittenWhenNothingWasCopied() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log)
        let capture = makeCapture(log: log, clipboard: clipboard)  // timeout: count never changes
        await #expect(throws: NotedropError("no_selected_text")) { try await capture.capture() }
        #expect(!log.all.contains("clipboard.write"))

        let log2 = CallLog()
        let clipboard2 = FakeClipboard(log: log2)
        let failing = makeCapture(log: log2, clipboard: clipboard2, sender: FakeSender(log: log2, error: NotedropError("boom")))
        await #expect(throws: NotedropError("boom")) { try await failing.capture() }
        #expect(!log2.all.contains("clipboard.write"))
    }

    @Test(arguments: ["automation_unavailable", "automation_failed"])
    func automationErrorsBecomePermissionMissing(_ code: String) async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log)
        let sender = FakeSender(log: log, error: NotedropError(code))
        let capture = makeCapture(log: log, clipboard: clipboard, sender: sender)
        do {
            _ = try await capture.capture()
            Issue.record("expected failure")
        } catch let error as NotedropError {
            #expect(error.code == "permission_missing")
            #expect(error.detail?.isEmpty == false)
        }
    }

    @Test func restoreFailureIsAWarningNotAFailure() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log)
        let sender = FakeSender(log: log) {
            clipboard.simulateCopy("copied")
            clipboard.writeError = NotedropError("clipboard_unavailable")
        }
        let draft = try await makeCapture(log: log, clipboard: clipboard, sender: sender).capture()
        #expect(draft.text == "copied")
        #expect(draft.warnings.map(\.code) == ["clipboard_restore_failed"])
    }

    @Test func backupFailureWarnsContinuesAndStillAttemptsRestore() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log)
        clipboard.failBackupRead = NotedropError("clipboard_unavailable")
        let sender = FakeSender(log: log) { clipboard.simulateCopy("copied") }
        let draft = try await makeCapture(log: log, clipboard: clipboard, sender: sender).capture()
        #expect(log.all.contains("clipboard.write"))
        #expect(draft.warnings.map(\.code).contains("clipboard_backup_failed"))
    }

    // MARK: draft shape (P-07, P-10, M-03)

    @Test func trimsOnlyTrailingLineBreaksAndBuildsTheDraft() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log)
        let capture = makeCapture(log: log, reader: "  keep leading\r\n\n", clipboard: clipboard)
        let draft = try await capture.capture()
        #expect(draft.text == "  keep leading")
        #expect(draft.type == .text)
        #expect(draft.note == nil)
        #expect(draft.tags.isEmpty)
        #expect(draft.imagePNG == nil)
        #expect(draft.title == "Ideas")  // window title wins over body
        #expect(draft.source.appName == "Notes")
    }

    @Test func sourceFailureNeverBlocksCapture() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log)
        var collector = FakeCollector(log: log)
        collector.result = SourceResult(source: DropSource(), warnings: [CaptureWarning("metadata_failed")])
        let capture = makeCapture(log: log, reader: "text", clipboard: clipboard, collector: collector)
        let draft = try await capture.capture()
        #expect(draft.source == DropSource())
        #expect(draft.warnings.map(\.code) == ["metadata_failed"])
        #expect(draft.title == "text")
    }

    @Test func missingChangeCountFallsBackToComparingText() async throws {
        let log = CallLog()
        let clipboard = FakeClipboard(log: log, snapshot: ClipboardSnapshot(text: "before", png: nil), changeCount: nil)
        let sender = FakeSender(log: log) { clipboard.simulateCopy("after") }
        let draft = try await makeCapture(log: log, clipboard: clipboard, sender: sender).capture()
        #expect(draft.text == "after")
    }
}
