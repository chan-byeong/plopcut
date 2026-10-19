import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

/// Pinning from the Library (spec 2.4, 2.5, PLO-102). The fixture `image-drop` is pinned; the others are not.
@MainActor
@Suite struct PinModelTests {
    private static let pinnedFixture = "2026-01-03_110000_000000003_image-drop"
    private static let textFixture = "2026-01-01_090000_000000001_example-app"
    private static let koreanFixture = "2026-01-02_100000_000000002_drop"

    /// A model over a copy of the fixture storage, so tests may write.
    private func model() async throws -> (LibraryModel, URL) {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/swift-migration/fixtures/storage")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: copy)
        let model = LibraryModel(storageRoot: { copy })
        await model.reload()
        return (model, copy)
    }

    // L-16: the list starts with the Pinned section, and the pinned drop is not repeated in a date group.
    @Test func theListStartsWithThePinnedSection() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.sections.first?.section == .pinned)
        #expect(model.sections.first?.drops.map(\.id) == [Self.pinnedFixture])
        let dated = model.sections.dropFirst().flatMap(\.drops).map(\.id)
        #expect(!dated.contains(Self.pinnedFixture) && dated.count == 5)
        #expect(model.showsSectionHeaders)
    }

    // L-04 with pins: the fallback selection is the first row shown, which is the first pinned drop.
    @Test func theFallbackSelectionIsTheFirstVisibleRow() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.selectedID == Self.pinnedFixture)
    }

    // L-17: the Pinned collection counts pinned drops, clears the tag, keeps the type at all, and has no section header.
    @Test func thePinnedCollectionListsOnlyPinnedDrops() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.count(for: .pinned) == 1)
        model.collection = .tag("swift")
        model.collection = .pinned
        #expect(model.filter.tag == nil && model.filter.type == .all && model.filter.pinnedOnly)
        #expect(model.filtered.map(\.id) == [Self.pinnedFixture])
        #expect(model.selectedID == Self.pinnedFixture)
        #expect(!model.showsSectionHeaders)
        #expect(model.title == L10n.t("pinned"))
    }

    // L-18: pinning writes the pin, moves the drop to the Pinned section, keeps the selection and updates the count.
    @Test func pinningKeepsTheSelectionAndMovesTheDropUp() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = Self.textFixture
        await model.togglePin(id: Self.textFixture)
        #expect(model.selectedID == Self.textFixture)
        #expect(model.selectedDrop?.isPinned == true)
        #expect(model.sections.first?.drops.map(\.id) == [Self.textFixture, Self.pinnedFixture])
        #expect(model.count(for: .pinned) == 2)
        let meta = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("drops/\(Self.textFixture)/drop.json"))) as? [String: Any]
        #expect(meta?["pinnedAt"] is String)
        #expect(meta?["updatedAt"] as? String == "2026-01-01T09:00:00.000000001Z")

        await model.togglePin(id: Self.textFixture)
        #expect(model.selectedID == Self.textFixture && model.selectedDrop?.isPinned == false)
        #expect(model.count(for: .pinned) == 1)
    }

    // Unpinning in the Pinned collection removes the drop from the list, so the selection follows spec 1.6.
    @Test func unpinningInThePinnedCollectionMovesTheSelection() async throws {
        let (model, root) = try await model()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.togglePin(id: Self.koreanFixture)
        model.collection = .pinned
        model.selectedID = Self.koreanFixture
        await model.togglePin(id: Self.koreanFixture)
        #expect(model.filtered.map(\.id) == [Self.pinnedFixture])
        #expect(model.selectedID == Self.pinnedFixture)
    }

    @Test func aFailedPinShowsAnAlertAndChangesNothing() async throws {
        let (model, root) = try await model()
        try FileManager.default.removeItem(at: root)
        await model.togglePin(id: Self.textFixture)
        #expect(model.alertMessage != nil)
        #expect(model.drops.first { $0.id == Self.textFixture }?.isPinned == false)
    }
}

/// Icon action buttons: tooltip "Name (Shortcut)" and accessible names (spec 2.6, L-19, L-20).
@MainActor
@Suite struct PinPresentationTests {
    @Test func tooltipsShowTheNameAndTheShortcut() {
        L10n.languageOverride = "ko"
        defer { L10n.languageOverride = nil }
        #expect(DropAction.pin(pinned: false).tooltip == "고정 (⇧⌘P)")
        #expect(DropAction.pin(pinned: true).tooltip == "고정 해제 (⇧⌘P)")
        #expect(DropAction.pin(pinned: true).title == "고정 해제")
        #expect(DropAction.openSource.tooltip == "출처 열기")
        #expect(DropAction.exportMarkdown.tooltip == "Markdown 내보내기")
        #expect(DropAction.moveTrash.tooltip == "휴지통으로 이동 (⌘⌫)")
        #expect(DropAction.editBody.tooltip.hasSuffix(" (⌘E)"))
        #expect(DropAction.pin(pinned: false).shortcut == PinCommand.shortcut)
    }

    @Test func thePinShortcutIsShiftCommandPAndDoesNotClash() {
        #expect(PinCommand.shortcut.key == "p")
        #expect(PinCommand.shortcut.modifiers == [.command, .shift])
        #expect(PinCommand.shortcut != RefreshCommand.shortcut)
    }

    @Test func pinnedRowsAnnouncePinned() {
        L10n.languageOverride = "ko"
        defer { L10n.languageOverride = nil }
        let pinned = Drop(id: "1", type: .text, title: "제목", text: "본문", createdAt: "2026-01-01T09:00:00Z",
                          updatedAt: "2026-01-01T09:00:00Z", pinnedAt: "2026-01-01T10:00:00Z")
        var unpinned = pinned
        unpinned.pinnedAt = nil
        #expect(Formatting.rowAccessibilityLabel(pinned).hasSuffix(", 고정됨"))
        #expect(!Formatting.rowAccessibilityLabel(unpinned).contains("고정됨"))
    }
}
