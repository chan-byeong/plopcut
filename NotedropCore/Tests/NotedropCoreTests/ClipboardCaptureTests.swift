import Foundation
import Testing
@testable import NotedropCore

/// A clipboard whose change count can move during `read()`, like another app copying mid-read.
private final class StubClipboard: ClipboardAccess, @unchecked Sendable {
    var snapshot: ClipboardSnapshot
    var count: Int?
    var bumpDuringRead = false
    var readError: NotedropError?
    private(set) var writes = 0

    init(_ snapshot: ClipboardSnapshot, count: Int? = 5) {
        self.snapshot = snapshot
        self.count = count
    }

    var changeCount: Int? { count }

    func read() throws -> ClipboardSnapshot {
        if let readError { throw readError }
        if bumpDuringRead { count = count.map { $0 + 1 } }
        return snapshot
    }

    func write(_ snapshot: ClipboardSnapshot) throws { writes += 1 }
}

private struct StubCollector: SourceCollector {
    var result = SourceResult(source: DropSource(appName: "Safari", windowTitle: "Docs"), warnings: [CaptureWarning("chrome_url_failed")])
    func collect(from target: CaptureTarget?) async -> SourceResult { result }
}

private let png = Data([0x89, 0x50, 0x4E, 0x47])

@Suite struct ClipboardCaptureTests {
    private func capture(
        _ clipboard: StubClipboard, target: CaptureTarget? = CaptureTarget(processID: 10, name: "Safari"),
        selfPID: Int32 = 99
    ) async throws -> CaptureDraft {
        try await ClipboardCapture(
            clipboard: clipboard, collector: StubCollector(), frontmost: { target },
            isNotedrop: { $0?.processID == selfPID }
        ).capture()
    }

    // K-01
    @Test func rejectsContentChangedDuringRead() async {
        let clipboard = StubClipboard(ClipboardSnapshot(text: "hello"))
        clipboard.bumpDuringRead = true
        do { _ = try await capture(clipboard) } catch let error as NotedropError {
            #expect(error.code == "clipboard_changed")
        } catch { Issue.record("unexpected \(error)") }
    }

    @Test func acceptsAnUnchangedCountAndAnUnreportedCount() async throws {
        #expect(try await capture(StubClipboard(ClipboardSnapshot(text: "a"))).text == "a")
        #expect(try await capture(StubClipboard(ClipboardSnapshot(text: "a"), count: nil)).text == "a")
    }

    // K-02
    @Test func textOnlyBecomesATextDraft() async throws {
        let draft = try await capture(StubClipboard(ClipboardSnapshot(text: "line one\nline two")))
        #expect(draft.type == .text)
        #expect(draft.text == "line one\nline two")
        #expect(draft.imagePNG == nil)
    }

    @Test func mixedContentIsSavedAsTextWithoutAWarningForNow() async throws {
        let draft = try await capture(StubClipboard(ClipboardSnapshot(text: "caption", png: png)))
        #expect(draft.type == .text)
        #expect(draft.text == "caption")
        #expect(draft.imagePNG == nil)
        #expect(!draft.warnings.contains(CaptureWarning("clipboard_image_unavailable")))
    }

    @Test func imageOnlyIsReportedAsUnsupportedUntilImageSaving() async {
        await expectFailure(StubClipboard(ClipboardSnapshot(png: png)), code: "clipboard_image_unsupported")
    }

    @Test func emptyOrBlankClipboardFailsAsEmpty() async {
        await expectFailure(StubClipboard(ClipboardSnapshot()), code: "clipboard_empty")
        await expectFailure(StubClipboard(ClipboardSnapshot(text: "  \n ")), code: "clipboard_empty")
    }

    // K-03
    @Test func undecodableImageFallsBackToTextWithAWarning() async throws {
        let draft = try await capture(StubClipboard(ClipboardSnapshot(text: "kept", imageUnreadable: true)))
        #expect(draft.text == "kept")
        #expect(draft.warnings.contains(CaptureWarning("clipboard_image_unavailable")))
    }

    @Test func undecodableImageWithoutTextFails() async {
        await expectFailure(StubClipboard(ClipboardSnapshot(imageUnreadable: true)), code: "clipboard_image_unavailable")
    }

    @Test func readFailureIsReportedAsUnavailable() async {
        let clipboard = StubClipboard(ClipboardSnapshot(text: "x"))
        clipboard.readError = NotedropError("clipboard_unavailable")
        await expectFailure(clipboard, code: "clipboard_unavailable")
    }

    // K-05
    @Test func keepsTheSourceOfAnotherApp() async throws {
        let draft = try await capture(StubClipboard(ClipboardSnapshot(text: "body")))
        #expect(draft.source.appName == "Safari")
        #expect(draft.source.windowTitle == "Docs")
        #expect(draft.title == "Docs")
        #expect(draft.warnings.contains(CaptureWarning("chrome_url_failed")))
    }

    @Test func omitsNotedropAsSourceAndReinfersTheTitle() async throws {
        let notedrop = CaptureTarget(processID: 99, name: "Notedrop")
        let draft = try await capture(StubClipboard(ClipboardSnapshot(text: "first line\nsecond")), target: notedrop)
        #expect(draft.source == DropSource())
        #expect(draft.title == "first line")
        #expect(draft.warnings.isEmpty)
    }

    @Test func readsTheClipboardWithoutEverWritingIt() async throws {
        let clipboard = StubClipboard(ClipboardSnapshot(text: "x"))
        _ = try await capture(clipboard)
        #expect(clipboard.writes == 0)
    }

    private func expectFailure(_ clipboard: StubClipboard, code: String) async {
        do {
            _ = try await capture(clipboard)
            Issue.record("expected \(code)")
        } catch let error as NotedropError {
            #expect(error.code == code)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}
