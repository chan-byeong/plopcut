import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

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
        #expect(model.selectedID == model.sections.first?.drops.first?.id)
    }

    @Test func sidebarSelectionIsSingleAndFiltersCombine() async throws {
        let model = try await loadedModel()
        model.collection = .image
        #expect(model.filtered.allSatisfy { $0.type == .image })
        model.collection = .tag("swift")
        #expect(model.filtered.allSatisfy { $0.tags.contains("swift") })
        #expect(model.filter.type == .all)
        model.sources = [.app("Example App")]
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

/// Source filter (PLO-103, checklist L-18 to L-20) on a temporary library, never the user's folder.
@MainActor
@Suite struct SourceFilterModelTests {
    private let github = DropSource(appName: "Google Chrome", url: "https://www.github.com/plopcut")
    private let apple = DropSource(appName: "Google Chrome", url: "https://developer.apple.com/swift")
    private let terminal = DropSource(appName: "Terminal")

    private struct Library {
        let model: LibraryModel
        let ids: [String: String]
        @MainActor func drop(_ name: String) -> Drop { model.drops.first { $0.id == ids[name] }! }
    }

    /// gh1 and gh2 from github.com today (gh1 tagged), apple from developer.apple.com 40 days ago, term from Terminal
    /// (tagged), loose without any source.
    private func library() async throws -> Library {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plopcut-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DropStore(root: root)
        let old = DropStore(root: root, clock: { Date().addingTimeInterval(-40 * 86_400) })
        let ids = [
            "gh1": try store.saveText("swift one", title: "gh1", source: github, tags: ["x"], note: nil).id,
            "gh2": try store.saveText("two", title: "gh2", source: github, tags: [], note: nil).id,
            "apple": try old.saveText("swift docs", title: "apple", source: apple, tags: [], note: nil).id,
            "term": try store.saveText("make", title: "term", source: terminal, tags: ["x"], note: nil).id,
            "loose": try store.saveText("swift loose", title: "loose", source: DropSource(), tags: [], note: nil).id,
        ]
        let model = LibraryModel(storageRoot: { root })
        await model.reload()
        return Library(model: model, ids: ids)
    }

    private func titles(_ model: LibraryModel) -> Set<String> { Set(model.filtered.map(\.title)) }

    private func counts(_ list: [SourceCount]) -> [String] { list.map { "\($0.key.name) \($0.count)" } }

    @Test func removingOneChipKeepsTheOtherSources() async throws {
        let model = try await library().model
        model.sources = [.website("github.com"), .app("Terminal")]
        #expect(titles(model) == ["gh1", "gh2", "term"])
        model.removeSource(.website("github.com"))
        #expect(model.sources == [.app("Terminal")])
        #expect(titles(model) == ["term"])
        #expect(model.hasRefiningFilters)
    }

    @Test func clearingFiltersKeepsTheSidebarSelectionAndSearch() async throws {
        let model = try await library().model
        model.collection = .tag("x")
        model.search = "swift"
        model.sources = [.website("github.com")]
        model.dateRange = .today
        model.clearFilters()
        #expect(model.collection == .tag("x") && model.search == "swift")
        #expect(model.sources.isEmpty && model.dateRange == .all && !model.hasRefiningFilters)
    }

    @Test func showDropsFromSourceShowsTheLibraryFilteredToThatSourceOnly() async throws {
        let library = try await library()
        let model = library.model
        model.collection = .tag("x")
        model.sources = [.app("Terminal")]
        model.dateRange = .last30Days
        model.showDropsFromSource(of: library.drop("apple"))
        #expect(model.collection == .all)
        #expect(model.sources == [.website("developer.apple.com")])
        // The period stays, so the 40-day-old drop is still hidden until the period is cleared.
        #expect(model.dateRange == .last30Days && model.filtered.isEmpty)
        model.dateRange = .all
        #expect(titles(model) == ["apple"])
        model.showDropsFromSource(of: library.drop("gh1"))
        #expect(titles(model) == ["gh1", "gh2"])
    }

    @Test func showDropsFromSourceIgnoresADropWithoutSource() async throws {
        let library = try await library()
        let model = library.model
        model.collection = .text
        model.sources = [.app("Terminal")]
        #expect(!LibraryModel.hasSource(library.drop("loose")))
        #expect(LibraryModel.hasSource(library.drop("term")))
        model.showDropsFromSource(of: library.drop("loose"))
        #expect(model.collection == .text && model.sources == [.app("Terminal")])
    }

    @Test func popoverListsWebsitesAndAppsWithCounts() async throws {
        let model = try await library().model
        let groups = model.sourceGroups(matching: "")
        #expect(counts(groups.websites) == ["github.com 2", "developer.apple.com 1"])
        // Web drops are also counted under their browser (PLO-100).
        #expect(counts(groups.apps) == ["Google Chrome 3", "Terminal 1"])
    }

    @Test func choosingTheBrowserShowsItsWebDrops() async throws {
        let model = try await library().model
        model.sources = [.app("Google Chrome")]
        #expect(titles(model) == ["gh1", "gh2", "apple"])
    }

    @Test func popoverCountsIgnoreTheSourceFilterButFollowTheOtherConditions() async throws {
        let model = try await library().model
        model.sources = [.app("Terminal")]
        #expect(counts(model.sourceGroups(matching: "").websites) == ["github.com 2", "developer.apple.com 1"])
        model.search = "swift"
        #expect(counts(model.sourceGroups(matching: "").websites) == ["developer.apple.com 1", "github.com 1"])
        // A selected source stays listed with 0 so it can still be unchecked; unselected empty sources are hidden.
        #expect(counts(model.sourceGroups(matching: "").apps) == ["Google Chrome 2", "Terminal 0"])
        model.search = ""
        model.sources = []
        model.dateRange = .today
        #expect(counts(model.sourceGroups(matching: "").websites) == ["github.com 2"])
        model.collection = .tag("x")
        #expect(counts(model.sourceGroups(matching: "").websites) == ["github.com 1"])
        #expect(counts(model.sourceGroups(matching: "").apps) == ["Google Chrome 1", "Terminal 1"])
    }

    @Test func popoverSearchKeepsMatchingSourceNames() async throws {
        let model = try await library().model
        let groups = model.sourceGroups(matching: "  APPLE ")
        #expect(counts(groups.websites) == ["developer.apple.com 1"] && groups.apps.isEmpty)
        #expect(counts(model.sourceGroups(matching: "term").apps) == ["Terminal 1"])
        let none = model.sourceGroups(matching: "nothing")
        #expect(none.websites.isEmpty && none.apps.isEmpty)
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

    // STA-78: a stored permission failure is shown with a button that opens the Accessibility pane.
    @Test func missingPermissionAlertOpensTheAccessibilityPane() {
        var opened: URL?
        let model = LibraryModel(storageRoot: { URL(fileURLWithPath: "/nonexistent") }, openURL: { opened = $0 })
        model.pendingCapture.store(PlopcutError("permission_missing"))
        model.presentPendingCaptureError()
        #expect(model.alertMessage != nil)
        #expect(model.alertRecovery == .openAccessibilitySettings)
        model.performRecovery()
        #expect(opened?.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        #expect(model.alertMessage == nil && model.alertRecovery == nil)
    }

    @Test func storageFailureAlertOpensPlopcutSettings() {
        let model = LibraryModel(storageRoot: { URL(fileURLWithPath: "/nonexistent") }, openURL: { _ in })
        model.pendingCapture.store(PlopcutError("storage_unwritable", detail: "/secret/path"))
        model.presentPendingCaptureError()
        #expect(model.alertRecovery == .openPlopcutSettings)
        #expect(model.alertMessage?.contains("/secret") == false)
        model.performRecovery()
        #expect(model.collection == .settings)
    }

    @Test func alertsWithoutAFixHaveNoButtonAndDismissingClearsIt() {
        let model = LibraryModel(storageRoot: { URL(fileURLWithPath: "/nonexistent") }, openURL: { _ in })
        model.showAlert(forCode: "no_selected_text")
        #expect(model.alertMessage != nil && model.alertRecovery == nil)
        model.showAlert(forCode: "permission_missing")
        model.alertMessage = nil
        #expect(model.alertRecovery == nil)
    }
}
