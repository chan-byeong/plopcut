import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

/// Editing a drop's content with Done and Cancel (spec 2.6 "본문 편집", PLO-104).
@MainActor
@Suite struct BodyEditTests {
    let rigs = DropEditorTests()

    static func image(_ id: String = "pic") -> Drop {
        Drop(id: id, type: .image, title: "Pic", imagePath: "image.png",
             createdAt: "2026-01-01T00:00:00.000000000Z", updatedAt: "2026-01-01T00:00:00.000000000Z")
    }

    // E-07, E-08
    @Test func doneWritesTheEditedTextAndCloses() async throws {
        let rig = rigs.makeRig()
        #expect(rig.editor.beginBodyEdit(DropEditorTests.drop()))
        #expect(rig.editor.isEditingBody && rig.editor.bodyText == "body" && !rig.editor.bodyChanged)
        rig.editor.bodyText = "body fixed"
        #expect(rig.editor.bodyChanged)
        #expect(await rig.editor.finishBodyEdit())
        #expect(await rig.recorder.calls == [.init(id: "a", title: nil, note: nil, tags: nil, text: "body fixed")])
        #expect(!rig.editor.isEditingBody)
        #expect(rig.saved.drops.map(\.text) == ["body fixed"])
    }

    // E-08: Done without a change closes without writing, so `updatedAt` stays.
    @Test func doneWithoutAChangeWritesNothing() async throws {
        let rig = rigs.makeRig()
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.bodyText = "changed"
        rig.editor.bodyText = "body"
        #expect(await rig.editor.finishBodyEdit())
        #expect(await rig.recorder.calls.isEmpty)
        #expect(!rig.editor.isEditingBody)
    }

    // E-09
    @Test func emptyContentKeepsTheEditorOpenWithAnError() async throws {
        let rig = rigs.makeRig()
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.bodyText = "  \n\t"
        #expect(await rig.editor.finishBodyEdit() == false)
        #expect(await rig.recorder.calls.isEmpty)
        #expect(rig.editor.isEditingBody && rig.editor.bodyText == "  \n\t")
        #expect(rig.editor.bodyEdit?.state == .failed("empty_text"))
    }

    // E-09
    @Test func aFailedSaveKeepsTheEditorOpenAndDoneRetries() async throws {
        let rig = rigs.makeRig()
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.bodyText = "new text"
        await rig.recorder.setFailure(PlopcutError("storage_unwritable"))
        #expect(await rig.editor.finishBodyEdit() == false)
        #expect(rig.editor.isEditingBody && rig.editor.bodyText == "new text")
        #expect(rig.editor.bodyEdit?.state == .failed("storage_unwritable"))
        #expect(rig.saved.drops.isEmpty)
        await rig.recorder.setFailure(nil)
        #expect(await rig.editor.finishBodyEdit())
        #expect(await rig.recorder.calls.map(\.text) == ["new text", "new text"])
        #expect(!rig.editor.isEditingBody)
    }

    // E-07
    @Test func imageDropsCannotBeEdited() {
        let rig = rigs.makeRig(Self.image())
        #expect(!DropEditor.canEditBody(Self.image()))
        #expect(rig.editor.beginBodyEdit(Self.image()) == false)
        #expect(!rig.editor.isEditingBody)
        var unreadable = DropEditorTests.drop()
        unreadable.text = nil
        #expect(!DropEditor.canEditBody(unreadable))
    }

    // E-10: Cancel without a change ends at once.
    @Test func cancelWithoutAChangeEndsWithoutAsking() async throws {
        let rig = rigs.makeRig()
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.cancelBodyEdit()
        #expect(!rig.editor.isEditingBody && !rig.editor.isConfirmingDiscard)
        #expect(await rig.recorder.calls.isEmpty)
    }

    // E-10: Cancel with a change asks; Keep Editing returns to the text, Discard drops it without writing.
    @Test func cancelWithAChangeAsksFirst() async throws {
        let rig = rigs.makeRig()
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.bodyText = "typo fixed"
        rig.editor.cancelBodyEdit()
        #expect(rig.editor.isConfirmingDiscard && rig.editor.isEditingBody)
        rig.editor.keepEditing()
        #expect(!rig.editor.isConfirmingDiscard && rig.editor.bodyText == "typo fixed")
        rig.editor.cancelBodyEdit()
        rig.editor.confirmDiscard()
        #expect(!rig.editor.isConfirmingDiscard && !rig.editor.isEditingBody)
        #expect(await rig.recorder.calls.isEmpty)
    }

    // E-10: leaving for another drop with a change holds the move until the user answers.
    @Test func leavingWithAChangeHoldsTheMoveUntilAnswered() async throws {
        let rig = rigs.makeRig()
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.bodyText = "edited"
        var moved = 0
        rig.editor.requestLeave { moved += 1 }
        #expect(moved == 0 && rig.editor.isConfirmingDiscard)
        rig.editor.keepEditing()
        #expect(moved == 0 && rig.editor.bodyText == "edited")
        rig.editor.requestLeave { moved += 1 }
        rig.editor.confirmDiscard()
        #expect(moved == 1 && !rig.editor.isEditingBody)
    }

    // E-10: without a change, or without an editor, leaving needs no answer.
    @Test func leavingWithoutAChangeMovesAtOnce() {
        let rig = rigs.makeRig()
        var moved = 0
        rig.editor.requestLeave { moved += 1 }
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.requestLeave { moved += 1 }
        #expect(moved == 2 && !rig.editor.isEditingBody && !rig.editor.isConfirmingDiscard)
    }

    // Showing another drop (a delete, a reload) closes an editor of the drop that is no longer shown.
    @Test func showingAnotherDropClosesTheEditor() {
        let rig = rigs.makeRig()
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.bodyText = "edited"
        rig.editor.show(DropEditorTests.drop())
        #expect(rig.editor.bodyText == "edited", "the same drop keeps its editor")
        rig.editor.show(DropEditorTests.drop("b"))
        #expect(!rig.editor.isEditingBody)
        rig.editor.beginBodyEdit(DropEditorTests.drop("b"))
        rig.editor.forget("b")
        #expect(!rig.editor.isEditingBody)
    }

    // E-12: a pending note autosave and the content save each send only their own field and keep their own state.
    @Test func autosaveAndContentSaveDoNotOverwriteEachOther() async throws {
        let rig = rigs.makeRig()
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.setNote("note typed")
        rig.editor.bodyText = "content typed"
        #expect(await rig.editor.finishBodyEdit())
        #expect(rig.editor.state == .pending && rig.editor.draft.note == "note typed")
        await rigs.settle()
        await rig.clock.advance(DropEditor.debounce)
        await rigs.settle()
        #expect(await rig.recorder.calls == [
            .init(id: "a", title: nil, note: nil, tags: nil, text: "content typed"),
            .init(id: "a", title: nil, note: "note typed", tags: nil),
        ])
        #expect(rig.editor.state == .saved && rig.editor.draft.note == "note typed")
    }

    // E-12: a content save queued behind an autosave in flight waits for it, and each keeps its own state.
    @Test func aContentSaveWaitsForAnAutosaveInFlight() async throws {
        let rig = rigs.makeRig()
        rig.editor.setNote("first")
        await rig.recorder.setHold(true)
        let flush = Task { await rig.editor.flush() }
        await rigs.settle()
        await rig.recorder.setHold(false)
        rig.editor.beginBodyEdit(DropEditorTests.drop())
        rig.editor.bodyText = "second"
        let done = Task { await rig.editor.finishBodyEdit() }
        await rigs.settle()
        #expect(await rig.recorder.calls.map(\.note) == ["first"], "the content write waits its turn")
        #expect(rig.editor.bodyEdit?.state == .saving)
        await rig.recorder.release()
        await flush.value
        #expect(await done.value)
        #expect(await rig.recorder.calls.map(\.text) == [nil, "second"])
        #expect(rig.editor.state == .saved && rig.editor.draft.note == "first" && !rig.editor.isEditingBody)
    }
}
