import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

/// Content editing through LibraryModel: the saved text reaches the list and search, and a move away from unsaved
/// changes is held until the user answers (spec 2.6 "본문 편집", PLO-104).
@MainActor
@Suite struct BodyEditModelTests {
    private static let textID = "2026-01-01_090000_000000001_example-app"
    private static let otherTextID = "2026-01-02_100000_000000002_drop"
    private static let imageID = "2026-01-03_110000_000000003_image-drop"

    private func loaded() async throws -> (LibraryModel, URL) {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/swift-migration/fixtures/storage")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: copy)
        let model = LibraryModel(storageRoot: { copy })
        await model.reload()
        return (model, copy)
    }

    // E-08, E-11
    @Test func doneSavesTheContentAndUpdatesListAndSearch() async throws {
        let (model, root) = try await loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = Self.textID
        let before = try #require(model.selectedDrop)
        #expect(model.beginBodyEdit())
        model.editor.bodyText = "zebra crossing notes\n"
        #expect(await model.editor.finishBodyEdit())
        let onDisk = try String(contentsOf: root.appendingPathComponent("drops/\(Self.textID)/content.md"), encoding: .utf8)
        #expect(onDisk == "zebra crossing notes")
        #expect(model.selectedID == Self.textID)
        #expect(model.selectedDrop?.text == "zebra crossing notes")
        #expect(model.selectedDrop?.updatedAt != before.updatedAt)
        model.search = "zebra crossing"
        #expect(model.filtered.map(\.id) == [Self.textID])
    }

    // E-07
    @Test func imageDropsCannotStartAnEdit() async throws {
        let (model, root) = try await loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = Self.imageID
        #expect(!model.canEditBody)
        #expect(model.beginBodyEdit() == false)
        #expect(!model.editor.isEditingBody)
    }

    // E-10: picking another drop with unsaved changes keeps the selection until Discard.
    @Test func selectingAnotherDropIsHeldUntilDiscard() async throws {
        let (model, root) = try await loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = Self.textID
        model.beginBodyEdit()
        model.editor.bodyText = "unsaved"
        model.selectedID = Self.otherTextID
        #expect(model.selectedID == Self.textID && model.editor.isConfirmingDiscard)
        model.editor.keepEditing()
        #expect(model.selectedID == Self.textID && model.editor.bodyText == "unsaved")
        model.selectedID = Self.otherTextID
        model.editor.confirmDiscard()
        #expect(model.selectedID == Self.otherTextID && !model.editor.isEditingBody)
        let onDisk = try String(contentsOf: root.appendingPathComponent("drops/\(Self.textID)/content.md"), encoding: .utf8)
        #expect(onDisk != "unsaved")
    }

    // E-10: the list and the sidebar get the kept value back after a held move, so the clicked row does not stay lit.
    @Test func aHeldMoveHandsTheKeptValueBackToTheLists() async throws {
        let (model, root) = try await loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = Self.textID
        model.beginBodyEdit()
        model.editor.bodyText = "unsaved"
        model.listSelection = Self.otherTextID
        model.sidebarSelection = .image
        #expect(model.listSelection == Self.otherTextID && model.sidebarSelection == .image)
        for _ in 0..<10 { await Task.yield() }
        #expect(model.listSelection == Self.textID && model.sidebarSelection == .all)
        #expect(model.editor.isConfirmingDiscard)
    }

    // E-10: without changes the selection moves at once and the editor closes.
    @Test func selectingAnotherDropWithoutChangesMovesAtOnce() async throws {
        let (model, root) = try await loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = Self.textID
        model.beginBodyEdit()
        model.selectedID = Self.otherTextID
        #expect(model.selectedID == Self.otherTextID && !model.editor.isEditingBody && !model.editor.isConfirmingDiscard)
    }

    // E-10: switching the Collection (a sidebar row, or Show Drops from This Source) is held the same way.
    @Test func switchingTheCollectionIsHeldUntilDiscard() async throws {
        let (model, root) = try await loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = Self.textID
        model.beginBodyEdit()
        model.editor.bodyText = "unsaved"
        model.collection = .image
        #expect(model.collection == .all && model.editor.isConfirmingDiscard)
        model.editor.keepEditing()
        #expect(model.collection == .all && model.selectedID == Self.textID)
        model.collection = .image
        model.editor.confirmDiscard()
        #expect(model.collection == .image && model.selectedID == Self.imageID)
    }

    // Typing a search that hides the edited drop keeps it selected while the editor is open.
    @Test func aSearchThatHidesTheEditedDropKeepsItSelected() async throws {
        let (model, root) = try await loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = Self.textID
        model.beginBodyEdit()
        model.editor.bodyText = "unsaved"
        model.search = "no drop matches this"
        #expect(model.selectedID == Self.textID && model.editor.isEditingBody)
    }
}
