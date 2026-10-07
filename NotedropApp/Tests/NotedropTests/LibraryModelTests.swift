import Foundation
import NotedropCore
import Testing
@testable import Notedrop

@MainActor
@Suite struct LibraryModelTests {
    private func loadedModel() async throws -> LibraryModel {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/swift-migration/fixtures/storage")
        let model = LibraryModel(storageRoot: { root })
        await model.reload()
        return model
    }

    @Test func loadsFixturesAndSelectsFirst() async throws {
        let model = try await loadedModel()
        #expect(model.drops.count == 6)
        #expect(model.warnings.count == 1)
        #expect(model.selectedID == model.filtered.first?.id)
    }

    @Test func sidebarSelectionIsSingleAndFiltersCombine() async throws {
        let model = try await loadedModel()
        model.collection = .image
        #expect(model.filtered.allSatisfy { $0.type == .image })
        model.collection = .tag("swift")
        #expect(model.filtered.allSatisfy { $0.tags.contains("swift") })
        #expect(model.filter.type == .all)
        model.app = "Example App"
        #expect(model.hasRefiningFilters)
        model.clearFilters()
        #expect(model.collection == .tag("swift") && !model.hasRefiningFilters)
    }

    @Test func selectionFallsBackWhenFilteredOut() async throws {
        let model = try await loadedModel()
        model.selectedID = model.drops.first { $0.type == .image }?.id
        model.collection = .text
        #expect(model.selectedDrop?.type != .image)
        model.search = "no such text anywhere"
        #expect(model.selectedID == nil)
    }

    @Test func missingFolderShowsEmptyNotError() async throws {
        let model = LibraryModel(storageRoot: { FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID())") })
        await model.reload()
        #expect(model.drops.isEmpty && model.loadError == nil)
    }
}

@Suite struct FormattingTests {
    @Test func previewOrder() {
        let drop = Drop(id: "1", type: .text, title: "t", text: nil, source: DropSource(appName: "App"), note: nil, createdAt: "", updatedAt: "")
        #expect(Formatting.preview(drop) == "App")
        #expect(Formatting.preview(Drop(id: "2", type: .text, title: "t", createdAt: "", updatedAt: "")) == "No preview")
        #expect(Formatting.preview(Drop(id: "3", type: .text, title: "t", text: "\n\n first \nsecond", createdAt: "", updatedAt: "")) == "first")
    }

    @Test func localizedStrings() {
        L10n.languageOverride = "ko"
        #expect(L10n.t("dropCount", ["count": "3"]) == "3개의 드롭")
        L10n.languageOverride = "en"
        #expect(L10n.t("dropCount", ["count": "3"]) == "3 drops")
        L10n.languageOverride = nil
    }
}

@MainActor
@Suite struct PaneWidthSettingsTests {
    @Test func restoresAndSavesPaneWidths() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json"), defaultStorageFolder: dir)
        let model = LibraryModel(storageRoot: { dir }, settings: store)
        #expect(model.paneWidths == .default)
        model.savePaneWidths(PaneWidths(sidebar: 260, library: 400))
        #expect(try store.read().paneWidths == PaneWidths(sidebar: 260, library: 400))
        #expect(LibraryModel(storageRoot: { dir }, settings: store).paneWidths == PaneWidths(sidebar: 260, library: 400))
    }
}

/// Trash stand-in: removes the folder (success) or fails/leaves it in place.
struct FakeTrash: TrashMover {
    enum Mode: Sendable { case succeed, fail, silentlyKeep }
    let mode: Mode
    func trash(_ url: URL) throws {
        switch mode {
        case .succeed: try FileManager.default.removeItem(at: url)
        case .fail: throw NSError(domain: "test", code: 1)
        case .silentlyKeep: break
        }
    }
}

@MainActor
@Suite struct LibraryEditingTests {
    /// A model over a copy of the fixture storage, so tests may write.
    private func model(trash: FakeTrash.Mode = .succeed) async throws -> (LibraryModel, URL) {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/swift-migration/fixtures/storage")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: copy)
        let model = LibraryModel(storageRoot: { copy }, trash: FakeTrash(mode: trash))
        await model.reload()
        return (model, copy)
    }

    // E-06
    @Test func editingUpdatesTheListAndKeepsTheSelection() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(model.selectedID)
        model.editor.setNote("edited note")
        await model.editor.flush()
        #expect(model.selectedID == id)
        #expect(model.selectedDrop?.note == "edited note")
        #expect(model.drops.count == 6)
        let onDisk = try String(contentsOf: root.appendingPathComponent("drops/\(id)/note.md"), encoding: .utf8)
        #expect(onDisk == "edited note")
    }

    // E-06: an edit that no longer matches the active filter must not move the selection.
    @Test func editingKeepsTheSelectionEvenWhenTheFilterNoLongerMatches() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        model.collection = .tag("swift")
        let id = try #require(model.selectedID)
        let tag = "swift"
        model.editor.removeTag(tag)
        await model.editor.flush()
        #expect(model.selectedID == id)
        #expect(model.selectedDrop?.tags.contains(tag) == false)
        #expect(model.editor.dropID == id)
    }

    @Test func selectingAnotherDropShowsItsOwnFields() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = try #require(model.filtered.dropFirst().first)
        model.selectedID = other.id
        #expect(model.editor.dropID == other.id)
        #expect(model.editor.draft.title == other.title)
    }

    // S-16
    @Test func deleteMovesTheFolderAndSelectsAnotherDrop() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(model.selectedID)
        model.editor.setNote("will be discarded")
        let ok = await model.delete(id: id)
        #expect(ok)
        #expect(model.drops.count == 5)
        #expect(!model.drops.contains { $0.id == id })
        #expect(model.selectedID != id && model.selectedID != nil)
        #expect(model.editor.dropID == model.selectedID)
        #expect(model.notice == L10n.t("trashSuccess"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("drops/\(id)").path))
    }

    @Test func failedDeleteKeepsTheDropAndReports() async throws {
        for mode in [FakeTrash.Mode.fail, .silentlyKeep] {
            let (model, root) = try await model(trash: mode)
            defer { try? FileManager.default.removeItem(at: root) }
            let id = try #require(model.selectedID)
            let ok = await model.delete(id: id)
            #expect(!ok)
            #expect(model.drops.count == 6)
            #expect(model.selectedID == id)
            #expect(model.alertMessage != nil)
        }
    }

    // Spec 7
    @Test func exportWritesMarkdownAndFailureIsReported() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        let drop = try #require(model.selectedDrop)
        let target = root.appendingPathComponent("out.md")
        #expect(model.exportMarkdown(of: drop, to: target))
        #expect(try String(contentsOf: target, encoding: .utf8) == MarkdownExport.render(drop))
        #expect(model.notice == L10n.t("exportSuccess"))
        #expect(!model.exportMarkdown(of: drop, to: root.appendingPathComponent("missing/dir/out.md")))
        #expect(model.alertMessage != nil)
    }
}
