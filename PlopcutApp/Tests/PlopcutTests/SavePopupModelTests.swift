import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

@MainActor
@Suite struct SavePopupModelTests {
    private let draft = CaptureDraft(
        type: .text, title: "Ideas", text: "hello", source: DropSource(appName: "Notes", windowTitle: "Ideas"))

    private nonisolated static func drop(_ request: SaveRequest) -> Drop {
        Drop(id: "d1", type: .text, title: request.title, text: request.text, source: request.source,
             note: request.note, tags: request.tags, createdAt: "t", updatedAt: "t")
    }

    private func make(
        recent: [String] = [], save: @escaping @Sendable (SaveRequest) async throws -> Drop,
        saved: @escaping (Drop) -> Void = { _ in }, cancelled: @escaping () -> Void = {},
        log: EventLogging = NullEventLog()
    ) -> SavePopupModel {
        SavePopupModel(draft: draft, recentTags: recent, save: save, onSaved: saved, onCancel: cancelled, log: log)
    }

    // STA-84: a save failure shown in the popup is logged by code only.
    @Test func saveFailureIsLoggedWithTheCodeOnly() async {
        let log = LogRecorder()
        let model = make(save: { _ in throw PlopcutError("storage_unwritable", detail: "/Users/me/secret") },
                         log: log)
        model.note = "private note"
        await model.submit()
        #expect(model.errorMessage == L10n.t("storageFailure"))
        #expect(log.events == [.error(code: "storage_unwritable")])
    }

    @Test func successfulSaveLogsNothing() async {
        let log = LogRecorder()
        let model = make(save: { Self.drop($0) }, log: log)
        await model.submit()
        #expect(log.events.isEmpty)
    }

    @Test func savesTextWithNoteAndTags() async {
        var saved: Drop?
        let model = make(save: { Self.drop($0) }, saved: { saved = $0 })
        model.note = "  remember this \n"
        model.tagInput = "research, quote"
        model.registerTagInput()
        await model.submit()
        #expect(saved?.text == "hello")
        #expect(saved?.tags == ["research", "quote"])
        #expect(saved?.note == "  remember this \n")
        #expect(model.errorMessage == nil)
    }

    @Test func blankNoteIsSavedAsNoNote() async {
        var saved: Drop?
        let model = make(save: { Self.drop($0) }, saved: { saved = $0 })
        model.note = "  \n"
        await model.submit()
        #expect(saved?.note == nil)
    }

    @Test func tagTypedButNotConfirmedStillCounts() async {
        var saved: Drop?
        let model = make(save: { Self.drop($0) }, saved: { saved = $0 })
        model.tagInput = "later"
        await model.submit()
        #expect(saved?.tags == ["later"])
    }

    @Test func duplicateTagShowsHintAndIsNotAddedTwice() {
        let model = make(save: { _ in throw PlopcutError("unused") })
        model.tagInput = "a"
        model.registerTagInput()
        model.tagInput = "a"
        model.registerTagInput()
        #expect(model.tags == ["a"])
        #expect(model.tagMessage == L10n.t("tagAlreadyAdded"))
        model.addRecentTag("a")
        model.addRecentTag("b")
        #expect(model.tags == ["a", "b"])
        model.removeTag("a")
        #expect(model.tags == ["b"])
    }

    @Test func failureKeepsThePopupOpenAndShowsTheReason() async {
        var saved = false
        let model = make(save: { _ in throw PlopcutError("storage_unwritable") }, saved: { _ in saved = true })
        await model.submit()
        #expect(!saved)
        #expect(model.errorMessage == L10n.t("storageFailure"))
        #expect(!model.isSaving)
    }

    @Test func secondSubmitWhileSavingIsIgnored() async {
        let gate = Gate()
        let counter = SaveCounter()
        let model = make(save: { request in
            await counter.increment()
            await gate.wait()
            return Self.drop(request)
        })
        let first = Task { await model.submit() }
        while await counter.value == 0 { await Task.yield() }
        await model.submit()  // returns immediately: a save is running
        await gate.open()
        await first.value
        #expect(await counter.value == 1)
    }

    @Test func cancelCallsBackWithoutSaving() {
        var cancelled = false
        let model = make(save: { _ in throw PlopcutError("unused") }, cancelled: { cancelled = true })
        model.cancel()
        #expect(cancelled)
    }

    // A cancel during a save must not run, or the finishing save would close the next popup.
    @Test func cancelWhileSavingIsIgnored() async {
        let gate = Gate()
        let counter = SaveCounter()
        var cancelled = false
        let model = make(save: { request in
            await counter.increment()
            await gate.wait()
            return Self.drop(request)
        }, cancelled: { cancelled = true })
        let saving = Task { await model.submit() }
        while await counter.value == 0 { await Task.yield() }
        model.cancel()
        #expect(!cancelled)
        await gate.open()
        await saving.value
        model.cancel()
        #expect(cancelled)
    }

    @Test func sourceSummaryJoinsAvailablePartsOrFallsBack() {
        let known = make(save: { _ in throw PlopcutError("unused") })
        #expect(known.sourceSummary == "Notes · Ideas")
        let unknown = SavePopupModel(
            draft: CaptureDraft(type: .text, title: "t", text: "x"), recentTags: [],
            save: { _ in throw PlopcutError("unused") }, onSaved: { _ in }, onCancel: {})
        #expect(unknown.sourceSummary == L10n.t("unknown"))
    }
}

actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { isOpen = true; continuation?.resume(); continuation = nil }
}

actor SaveCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
