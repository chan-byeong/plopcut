import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

/// Hand-driven clock for the 600 ms debounce: tests decide when time passes.
actor ManualClock {
    private var waiters: [Int: (due: Duration, continuation: CheckedContinuation<Void, Error>)] = [:]
    private var now: Duration = .zero
    private var nextID = 0

    func sleep(for duration: Duration) async throws {
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler(operation: {
            try await self.park(id, duration)
        }, onCancel: {
            Task { await self.cancel(id) }
        })
    }

    private func park(_ id: Int, _ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
            waiters[id] = (now + duration, continuation)
        }
    }

    private func cancel(_ id: Int) {
        waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }

    func advance(_ duration: Duration) async {
        now += duration
        let due = waiters.filter { $0.value.due <= now }
        for id in due.keys { waiters.removeValue(forKey: id) }
        for entry in due.values { entry.continuation.resume() }
        for _ in 0..<20 { await Task.yield() }
    }
}

/// Records every save and lets a test hold a response until it chooses to release it.
actor SaveRecorder {
    struct Call: Equatable { var id: String; var title: String?; var note: String?; var tags: [String]? }
    private(set) var calls: [Call] = []
    var failure: PlopcutError?
    private var gates: [CheckedContinuation<Void, Never>] = []
    var holdNext = false

    func setFailure(_ error: PlopcutError?) { failure = error }
    func setHold(_ hold: Bool) { holdNext = hold }
    func release() { let all = gates; gates.removeAll(); for gate in all { gate.resume() } }

    func save(_ id: String, _ update: DropUpdate, base: Drop) async throws -> Drop {
        calls.append(Call(id: id, title: update.title, note: update.note, tags: update.tags))
        if holdNext { await withCheckedContinuation { gates.append($0) } }
        if let failure { throw failure }
        var drop = base
        if let title = update.title { drop.title = title }
        if let note = update.note { drop.note = note }
        if let tags = update.tags { drop.tags = tags }
        return drop
    }
}

@MainActor
@Suite struct DropEditorTests {
    static func drop(_ id: String = "a", title: String = "Title", note: String? = nil, tags: [String] = []) -> Drop {
        Drop(id: id, type: .text, title: title, text: "body", note: note, tags: tags,
             createdAt: "2026-01-01T00:00:00.000000000Z", updatedAt: "2026-01-01T00:00:00.000000000Z")
    }

    struct Rig {
        let editor: DropEditor
        let clock: ManualClock
        let recorder: SaveRecorder
        var saved: SavedBox
    }
    final class SavedBox { var drops: [Drop] = []; var failures: [String] = [] }

    func makeRig(_ initial: Drop = DropEditorTests.drop(), log: EventLogging = NullEventLog()) -> Rig {
        let clock = ManualClock(), recorder = SaveRecorder(), box = SavedBox()
        let editor = DropEditor(
            sleep: { try await clock.sleep(for: $0) },
            save: { id, update in try await recorder.save(id, update, base: initial) },
            onSaved: { box.drops.append($0) },
            onBackgroundFailure: { box.failures.append($0) },
            log: log)
        editor.show(initial)
        return Rig(editor: editor, clock: clock, recorder: recorder, saved: box)
    }

    func settle() async { for _ in 0..<30 { await Task.yield() } }

    // E-01
    @Test func savesSixHundredMillisecondsAfterTheLastEdit() async throws {
        let rig = makeRig()
        rig.editor.setNote("one")
        #expect(rig.editor.state == .pending)
        await settle()
        await rig.clock.advance(.milliseconds(400))
        rig.editor.setNote("one two")
        await settle()
        await rig.clock.advance(.milliseconds(400))
        #expect(await rig.recorder.calls.isEmpty)
        await rig.clock.advance(.milliseconds(200))
        await settle()
        #expect(await rig.recorder.calls == [.init(id: "a", title: nil, note: "one two", tags: nil)])
        #expect(rig.editor.state == .saved)
        #expect(rig.saved.drops.map(\.note) == ["one two"])
    }

    @Test func leavingTheFieldSavesImmediately() async throws {
        let rig = makeRig()
        rig.editor.setNote("quick")
        await rig.editor.flush()
        #expect(await rig.recorder.calls.count == 1)
        #expect(rig.editor.state == .saved)
        await rig.clock.advance(.seconds(2))
        #expect(await rig.recorder.calls.count == 1, "the pending debounce must not save a second time")
    }

    // E-03
    @Test func noChangeMeansNoSave() async throws {
        let rig = makeRig()
        rig.editor.setNote("x")
        rig.editor.setNote("")
        await rig.editor.flush()
        #expect(await rig.recorder.calls.isEmpty)
        #expect(rig.editor.state == .saved)
    }

    // E-04
    @Test func blankTitleIsNotSavedAndReportsBlankTitle() async throws {
        let rig = makeRig()
        rig.editor.setTitle("   ")
        await rig.editor.flush()
        #expect(await rig.recorder.calls.isEmpty)
        #expect(rig.editor.state == .failed("blankTitle"))
        await rig.editor.flush()
        #expect(rig.editor.state == .failed("blankTitle"), "blur does not retry a failed save")
    }

    @Test func failureStopsBlurRetriesUntilRetryOrNewEdit() async throws {
        let rig = makeRig()
        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        rig.editor.setNote("n")
        await rig.editor.flush()
        #expect(rig.editor.state == .failed("storage_unwritable"))
        await rig.editor.flush()
        #expect(await rig.recorder.calls.count == 1)

        await rig.recorder.setFailure(nil)
        await rig.editor.retry()
        #expect(await rig.recorder.calls.count == 2)
        #expect(rig.editor.state == .saved)
    }

    // STA-84: a failed autosave is logged by code only, once, not again while retries keep failing.
    @Test func failedAutosaveLogsTheCodeOnceAndNeverTheContent() async throws {
        let log = LogRecorder()
        let rig = makeRig(log: log)
        await rig.recorder.setFailure(PlopcutError("storage_unwritable", detail: "/Users/me/secret/path"))
        rig.editor.setNote("private note text")
        rig.editor.setTitle("Private title")
        rig.editor.setNote("private note text 2")
        await rig.editor.flush()
        #expect(log.events == [.error(code: "storage_unwritable")])
        await rig.editor.flush()
        await rig.editor.retry()
        await rig.editor.retry()
        #expect(log.events == [.error(code: "storage_unwritable")])
        #expect(log.events.map(\.line) == ["error code=storage_unwritable"])
    }

    @Test func autosaveFailureAfterARecoveryIsLoggedAgain() async throws {
        let log = LogRecorder()
        let rig = makeRig(log: log)
        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        rig.editor.setNote("a")
        await rig.editor.flush()
        await rig.recorder.setFailure(nil)
        await rig.editor.retry()
        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        rig.editor.setNote("b")
        await rig.editor.flush()
        #expect(log.events.count == 2)
    }

    @Test func editingAfterAFailureArmsTheDebounceAgain() async throws {
        let rig = makeRig()
        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        rig.editor.setNote("n")
        await rig.editor.flush()
        await rig.recorder.setFailure(nil)
        rig.editor.setNote("n2")
        #expect(rig.editor.state == .pending)
        await settle()
        await rig.clock.advance(.milliseconds(600))
        await settle()
        #expect(rig.editor.state == .saved)
    }

    // E-02
    @Test func lateResponseDoesNotOverwriteNewerEdit() async throws {
        let rig = makeRig()
        await rig.recorder.setHold(true)
        rig.editor.setNote("first")
        let flushing = Task { await rig.editor.flush() }
        await settle()
        #expect(rig.editor.state == .saving)
        rig.editor.setNote("second")
        await rig.recorder.setHold(false)
        await rig.recorder.release()
        await flushing.value
        #expect(rig.editor.draft.note == "second")
        #expect(rig.editor.state == .pending, "a newer edit is still unsaved")
        await settle()
        await rig.clock.advance(.milliseconds(600))
        await settle()
        #expect(await rig.recorder.calls.map(\.note) == ["first", "second"])
        #expect(rig.editor.state == .saved)
    }

    @Test func switchingDropsSavesTheOldOneAndResetsTheEditor() async throws {
        let rig = makeRig()
        rig.editor.setNote("unsaved")
        rig.editor.show(Self.drop("b", title: "Other"))
        await settle()
        #expect(await rig.recorder.calls == [.init(id: "a", title: nil, note: "unsaved", tags: nil)])
        #expect(rig.editor.draft.title == "Other")
        #expect(rig.editor.draft.note == "")
        #expect(rig.editor.state == .idle)
    }

    @Test func refreshKeepsDraftWhileEditingAndRebasesWhenClean() async throws {
        let rig = makeRig()
        rig.editor.setNote("typing")
        rig.editor.show(Self.drop("a", title: "Renamed elsewhere"))
        #expect(rig.editor.draft.note == "typing")
        await rig.editor.flush()
        rig.editor.show(Self.drop("a", title: "Renamed elsewhere", note: "disk"))
        #expect(rig.editor.draft.title == "Renamed elsewhere")
        #expect(rig.editor.draft.note == "disk")
    }

    // I-02
    @Test func addingTagsSplitsOnCommasAndReportsDuplicates() async throws {
        let rig = makeRig(Self.drop(tags: ["swift"]))
        #expect(rig.editor.addTags("Rust, #go") == .added)
        #expect(rig.editor.draft.tags == ["swift", "rust", "go"])
        #expect(rig.editor.addTags("SWIFT") == .alreadyAdded)
        #expect(rig.editor.draft.tags == ["swift", "rust", "go"])
        #expect(rig.editor.addTags("  ,  ") == .nothing)
        #expect(rig.editor.addTags("go, python") == .added, "new tags are added even when one is a duplicate")
        #expect(rig.editor.draft.tags.last == "python")
        rig.editor.removeTag("rust")
        #expect(rig.editor.draft.tags == ["swift", "go", "python"])
        await rig.editor.flush()
        #expect(await rig.recorder.calls.last?.tags == ["swift", "go", "python"])
    }

    @Test func titleRevertDropsTheUncommittedText() async throws {
        let rig = makeRig()
        rig.editor.beginTitleEdit()
        rig.editor.titleText = "Half typed"
        rig.editor.cancelTitleEdit()
        #expect(rig.editor.titleText == "Title")
        await rig.editor.flush()
        #expect(await rig.recorder.calls.isEmpty)
        rig.editor.beginTitleEdit()
        rig.editor.titleText = "New title"
        await rig.editor.commitTitle()
        #expect(await rig.recorder.calls == [.init(id: "a", title: "New title", note: nil, tags: nil)])
    }

    // E-02: reverting while a save is in flight must survive the response.
    @Test func revertingDuringASaveIsNotOverwrittenByTheResponse() async throws {
        let rig = makeRig()
        await rig.recorder.setHold(true)
        rig.editor.setNote("first")
        let flushing = Task { await rig.editor.flush() }
        await settle()
        rig.editor.setNote("")           // back to what is on disk before the save
        await rig.recorder.setHold(false)
        await rig.recorder.release()
        await flushing.value
        #expect(rig.editor.draft.note == "")
        await settle()
        await rig.clock.advance(.milliseconds(600))
        await settle()
        #expect(await rig.recorder.calls.map(\.note) == ["first", ""], "the revert is written after the first save")
    }

    // E-02: saves are written one at a time, in order.
    @Test func overlappingSavesAreSerialized() async throws {
        let rig = makeRig()
        await rig.recorder.setHold(true)
        rig.editor.setNote("one")
        let first = Task { await rig.editor.flush() }
        await settle()
        rig.editor.setNote("two")
        let second = Task { await rig.editor.flush() }
        await settle()
        #expect(await rig.recorder.calls.map(\.note) == ["one"], "the second save waits for the first")
        await rig.recorder.setHold(false)
        await rig.recorder.release()
        await first.value; await second.value
        #expect(await rig.recorder.calls.map(\.note) == ["one", "two"])
        #expect(rig.editor.state == .saved)
    }

    // Leaving a drop whose save fails keeps the draft and says so.
    @Test func failedBackgroundSaveParksTheDraftAndReportsIt() async throws {
        let rig = makeRig()
        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        rig.editor.setNote("precious")
        rig.editor.show(Self.drop("b", title: "Other"))
        await settle()
        #expect(rig.saved.failures == ["storage_unwritable"])
        #expect(rig.editor.draft.title == "Other")
        rig.editor.show(Self.drop("a"))
        #expect(rig.editor.draft.note == "precious")
        #expect(rig.editor.state == .failed("storage_unwritable"))
        await rig.recorder.setFailure(nil)
        await rig.editor.retry()
        #expect(rig.editor.state == .saved)
    }

    // A save response must not wipe a title that is being typed.
    @Test func saveResponseKeepsTitleBeingTyped() async throws {
        let rig = makeRig()
        await rig.recorder.setHold(true)
        rig.editor.setNote("n")
        let flushing = Task { await rig.editor.flush() }
        await settle()
        rig.editor.beginTitleEdit()
        rig.editor.titleText = "Typing a new tit"
        await rig.recorder.setHold(false)
        await rig.recorder.release()
        await flushing.value
        #expect(rig.editor.titleText == "Typing a new tit")
    }

    @Test func pendingEditsAreReportedForTermination() async throws {
        let rig = makeRig()
        #expect(!rig.editor.hasUnsavedEdits)
        rig.editor.setNote("x")
        #expect(rig.editor.hasUnsavedEdits)
        await rig.editor.flush()
        #expect(!rig.editor.hasUnsavedEdits)
    }

    // Switching away while a save is in flight and reverting in between: the revert must still be written.
    @Test func revertThenSwitchDuringASaveStillWritesTheRevert() async throws {
        let rig = makeRig()
        await rig.recorder.setHold(true)
        rig.editor.setNote("first")
        let flushing = Task { await rig.editor.flush() }
        await settle()
        rig.editor.setNote("")
        rig.editor.show(Self.drop("b", title: "Other"))
        await rig.recorder.setHold(false)
        await rig.recorder.release()
        await flushing.value
        await settle()
        let notes = await rig.recorder.calls.map(\.note)
        #expect(notes == ["first", ""], "calls were \(notes)")
        #expect(rig.editor.hasUnsavedEdits == false)
    }

    // Coming back to a drop whose background save has not finished shows its draft, and a later visit has no stale copy.
    @Test func returningBeforeTheBackgroundSaveFinishes() async throws {
        let rig = makeRig()
        await rig.recorder.setHold(true)
        rig.editor.setNote("typed")
        rig.editor.show(Self.drop("b", title: "Other"))
        await settle()
        rig.editor.show(Self.drop("a"))
        #expect(rig.editor.draft.note == "typed")
        #expect(rig.editor.state == .saving)
        await rig.recorder.setHold(false)
        await rig.recorder.release()
        await settle()
        #expect(rig.editor.state == .saved)
        rig.editor.show(Self.drop("b", title: "Other"))
        rig.editor.show(Self.drop("a", note: "typed"))
        #expect(rig.editor.draft.note == "typed")
        #expect(!rig.editor.hasUnsavedEdits)
    }

    @Test func failedDraftIsNotResurrectedAfterALaterSuccessfulSave() async throws {
        let rig = makeRig()
        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        rig.editor.setNote("old")
        rig.editor.show(Self.drop("b", title: "Other"))
        await settle()
        rig.editor.show(Self.drop("a"))
        await rig.recorder.setFailure(nil)
        rig.editor.setNote("newer")
        await rig.editor.flush()
        #expect(rig.editor.state == .saved)
        rig.editor.show(Self.drop("b", title: "Other"))
        rig.editor.show(Self.drop("a", note: "newer"))
        #expect(rig.editor.draft.note == "newer")
        #expect(!rig.editor.hasUnsavedEdits)
    }

    // Quitting right after switching: the edit made before the switch is still counted and drained.
    @Test func drainWritesBackgroundEditsAndReportsFailure() async throws {
        let rig = makeRig()
        rig.editor.setNote("edit")
        rig.editor.show(Self.drop("b", title: "Other"))
        #expect(rig.editor.hasUnsavedEdits)
        #expect(await rig.editor.drain())
        #expect(await rig.recorder.calls.map(\.note) == ["edit"])
        #expect(!rig.editor.hasUnsavedEdits)

        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        rig.editor.setNote("again")
        #expect(await rig.editor.drain() == false)
        #expect(rig.editor.hasUnsavedEdits, "a failed save still counts as unsaved")
    }

    // E-04: leaving the title untouched must not retry a failed note save.
    @Test func unchangedTitleBlurDoesNotRetryAFailedSave() async throws {
        let rig = makeRig()
        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        rig.editor.setNote("n")
        await rig.editor.flush()
        let calls = await rig.recorder.calls.count
        rig.editor.beginTitleEdit()
        await rig.editor.commitTitle()
        #expect(rig.editor.state == .failed("storage_unwritable"))
        #expect(await rig.recorder.calls.count == calls)
    }

    // A title typed but not yet committed is saved when the selection moves away.
    @Test func switchingDropsKeepsAnUncommittedTitle() async throws {
        let rig = makeRig()
        rig.editor.beginTitleEdit()
        rig.editor.titleText = "Renamed on the way out"
        rig.editor.show(Self.drop("b", title: "Other"))
        await settle()
        #expect(await rig.recorder.calls == [.init(id: "a", title: "Renamed on the way out", note: nil, tags: nil)])
        #expect(rig.editor.titleText == "Other")
        await rig.editor.commitTitle()   // the late blur must not touch the new drop
        #expect(await rig.recorder.calls.count == 1)
    }

    // E-04: a blur queued while a save runs must not retry that save after it fails.
    @Test func blurQueuedDuringASaveDoesNotRetryAfterItFails() async throws {
        let rig = makeRig()
        await rig.recorder.setHold(true)
        rig.editor.setNote("n")
        let first = Task { await rig.editor.flush() }
        await settle()
        rig.editor.beginTitleEdit()
        let blur = Task { await rig.editor.commitTitle() }
        await settle()
        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        await rig.recorder.setHold(false)
        await rig.recorder.release()
        await first.value; await blur.value
        #expect(await rig.recorder.calls.count == 1)
        #expect(rig.editor.state == .failed("storage_unwritable"))
    }
}
