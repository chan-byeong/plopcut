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
