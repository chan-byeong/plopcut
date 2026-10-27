import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

/// F-09: a floating panel's note shares the editing state of its drop with the inspector (spec 2.7, 2.8).
@MainActor
@Suite struct FloatingNoteTests {
    private static let a = DropEditorTests.drop("a", note: "start")
    private static let b = DropEditorTests.drop("b")

    private struct Rig {
        let editor: DropEditor
        let clock: ManualClock
        let recorder: SaveRecorder
        let failures: Box
    }
    private final class Box { var codes: [String] = [] }

    /// The inspector shows `selected`; saves answer with the drop the id names.
    private func makeRig(selected: Drop) -> Rig {
        let clock = ManualClock(), recorder = SaveRecorder(), failures = Box()
        let drops = [Self.a.id: Self.a, Self.b.id: Self.b]
        let editor = DropEditor(
            sleep: { try await clock.sleep(for: $0) },
            save: { id, update in try await recorder.save(id, update, base: drops[id]!) },
            onSaved: { _ in },
            onBackgroundFailure: { failures.codes.append($0) },
            log: NullEventLog())
        editor.show(selected)
        return Rig(editor: editor, clock: clock, recorder: recorder, failures: failures)
    }

    private func settle() async { for _ in 0..<30 { await Task.yield() } }

    private func debounce(_ rig: Rig) async {
        await settle()
        await rig.clock.advance(DropEditor.debounce)
        await settle()
    }

    @Test func typingInTurnInTheInspectorAndThePanelSavesTheLastTextOnce() async {
        let rig = makeRig(selected: Self.a)
        rig.editor.attachPanel("a")
        rig.editor.setNote("one", of: Self.a)
        #expect(rig.editor.draft.note == "one")
        rig.editor.setNote("one two")
        #expect(rig.editor.note(of: Self.a) == "one two")
        rig.editor.setNote("one two three", of: Self.a)
        await debounce(rig)
        #expect(await rig.recorder.calls == [.init(id: "a", title: nil, note: "one two three", tags: nil)])
        #expect(rig.editor.state == .saved)
        #expect(rig.editor.saveState(of: "a") == .saved)
    }

    @Test func aPanelOnAnotherDropSavesAfterTheDebounceWithoutTouchingTheInspector() async {
        let rig = makeRig(selected: Self.b)
        rig.editor.attachPanel("a")
        #expect(rig.editor.note(of: Self.a) == "start")
        rig.editor.setNote("panel", of: Self.a)
        #expect(rig.editor.saveState(of: "a") == .pending)
        #expect(rig.editor.state == .idle && rig.editor.draft.note == "")
        await debounce(rig)
        #expect(await rig.recorder.calls == [.init(id: "a", title: nil, note: "panel", tags: nil)])
        #expect(rig.editor.saveState(of: "a") == .saved)
        #expect(!rig.editor.hasUnsavedEdits)
    }

    @Test func choosingAnotherDropInTheInspectorKeepsThePanelsTyping() async {
        let rig = makeRig(selected: Self.a)
        rig.editor.attachPanel("a")
        await rig.recorder.setHold(true)
        rig.editor.setNote("typing", of: Self.a)
        rig.editor.show(Self.b)
        await settle()
        #expect(rig.editor.note(of: Self.a) == "typing")
        rig.editor.setNote("typing more", of: Self.a)
        await rig.recorder.setHold(false)
        await rig.recorder.release()
        await debounce(rig)
        // Once saved, the panel reads the note from the Library's drop, which the save updated.
        #expect(await rig.recorder.calls.map(\.note) == ["typing", "typing more"])
        #expect(rig.editor.saveState(of: "a") == .saved)
    }

    @Test func aLateResponseDoesNotOverwriteNewerTyping() async {
        let rig = makeRig(selected: Self.b)
        rig.editor.attachPanel("a")
        await rig.recorder.setHold(true)
        rig.editor.setNote("one", of: Self.a)
        await debounce(rig)
        #expect(rig.editor.saveState(of: "a") == .saving)
        rig.editor.setNote("one two", of: Self.a)
        await rig.recorder.setHold(false)
        await rig.recorder.release()
        await settle()
        #expect(rig.editor.note(of: Self.a) == "one two")
        #expect(rig.editor.saveState(of: "a") == .pending)
        await debounce(rig)
        #expect(await rig.recorder.calls.map(\.note) == ["one", "one two"])
        #expect(rig.editor.saveState(of: "a") == .saved)
    }

    @Test func aFailureShowsRetryOnBothSidesAndLeavingTheFieldDoesNotRetry() async {
        let rig = makeRig(selected: Self.a)
        rig.editor.attachPanel("a")
        await rig.recorder.setFailure(PlopcutError("write_failed"))
        rig.editor.setNote("lost?", of: Self.a)
        await debounce(rig)
        #expect(rig.editor.state == .failed("write_failed"))
        #expect(rig.editor.saveState(of: "a") == .failed("write_failed"))
        await rig.editor.flushNote(of: "a")
        #expect(await rig.recorder.calls.count == 1)
        await rig.recorder.setFailure(nil)
        await rig.editor.retryNote(of: "a")
        #expect(rig.editor.state == .saved)
        #expect(await rig.recorder.calls.count == 2)
    }

    @Test func aPanelsFailureIsShownInThePanelNotAsAnAlert() async {
        let rig = makeRig(selected: Self.b)
        rig.editor.attachPanel("a")
        await rig.recorder.setFailure(PlopcutError("write_failed"))
        rig.editor.setNote("x", of: Self.a)
        await debounce(rig)
        #expect(rig.editor.saveState(of: "a") == .failed("write_failed"))
        #expect(rig.failures.codes.isEmpty)
        await rig.editor.detachPanel("a")
        #expect(rig.failures.codes == ["write_failed"])
        #expect(rig.editor.hasUnsavedEdits)
    }

    @Test func closingThePanelSavesWhatWasTypedAtOnce() async {
        let rig = makeRig(selected: Self.b)
        rig.editor.attachPanel("a")
        rig.editor.setNote("bye", of: Self.a)
        await rig.editor.detachPanel("a")
        #expect(await rig.recorder.calls == [.init(id: "a", title: nil, note: "bye", tags: nil)])
        #expect(!rig.editor.hasUnsavedEdits)
        #expect(rig.editor.saveState(of: "a") == .idle)
    }

    @Test func quittingSavesAPanelsNote() async {
        let rig = makeRig(selected: Self.b)
        rig.editor.attachPanel("a")
        rig.editor.setNote("before quit", of: Self.a)
        #expect(rig.editor.needsWorkBeforeQuit)
        #expect(await rig.editor.drain())
        #expect(await rig.recorder.calls.map(\.note) == ["before quit"])
    }

    @Test func theInspectorTakesOverAPanelsDraft() async {
        let rig = makeRig(selected: Self.b)
        rig.editor.attachPanel("a")
        rig.editor.setNote("from panel", of: Self.a)
        rig.editor.show(Self.a)
        #expect(rig.editor.draft.note == "from panel")
        #expect(rig.editor.state == .pending)
        await debounce(rig)
        #expect(await rig.recorder.calls.map(\.note) == ["from panel"])
        #expect(rig.editor.state == .saved)
    }
}
