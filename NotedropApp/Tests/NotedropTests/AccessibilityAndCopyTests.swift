import AppKit
import Foundation
import NotedropCore
import Testing
@testable import Notedrop

/// STA-80: VoiceOver labels and copy consistency. None of these touch `L10n.languageOverride`.
@Suite struct AccessibilityAndCopyTests {
    private static func isText(_ text: String, ofKey key: String) -> Bool {
        text == StringTable.entries[key]?.en || text == StringTable.entries[key]?.ko
    }

    private static let sample = Drop(
        id: "1", type: .image, title: "Release notes", source: DropSource(appName: "Safari"), tags: ["a", "b"],
        createdAt: "2026-01-01T09:00:00Z", updatedAt: "2026-01-01T09:00:00Z")

    @Test func aListRowReadsAsOnePhraseWithTitleTypeAppAndTags() {
        let label = Formatting.rowAccessibilityLabel(Self.sample)
        #expect(label.hasPrefix("Release notes, "))
        #expect(label.contains("Safari") && label.contains("#a #b"))
        #expect(label.contains(StringTable.entries["image"]!.en) || label.contains(StringTable.entries["image"]!.ko))
        #expect(!label.contains(", ,"))
    }

    @Test func aBareRowHasNoEmptySegments() {
        let bare = Drop(id: "2", type: .text, title: "T", createdAt: "bad", updatedAt: "bad")
        let label = Formatting.rowAccessibilityLabel(bare)
        #expect(!label.contains(", ,") && !label.hasSuffix(", "))
    }

    @Test func oneDropUsesTheSingularPhrase() {
        #expect(Self.isText(Formatting.dropCount(1), ofKey: "dropCountOne"))
        #expect(!Formatting.dropCount(1).contains("{count}"))
        #expect(Formatting.dropCount(5).contains("5"))
    }

    @Test func accessibilityLabelKeysExistInBothLanguages() {
        for key in ["dropTitle", "ok", "unreadableDrops", "dropCountOne", "removeTag", "tags", "note", "image", "librarySidebar", "appLogo"] {
            #expect(StringTable.entries[key] != nil, "\(key)")
        }
    }

    /// strings.md is the source of truth; StringTable must carry the same keys and texts.
    @Test func stringTableMatchesStringsMarkdown() throws {
        let doc = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/swift-migration/strings.md")
        let text = try String(contentsOf: doc, encoding: .utf8)
        var documented: [String: (en: String, ko: String)] = [:]
        for line in text.split(separator: "\n") where line.hasPrefix("| `") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 3 else { continue }
            documented[cells[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))] = (cells[1], cells[2])
        }
        #expect(Set(documented.keys) == Set(StringTable.entries.keys))
        for (key, entry) in StringTable.entries {
            // shortcutFormatHint is rewritten for the Swift shortcut format (checklist D-12); the doc keeps the legacy wording.
            if key == "shortcutFormatHint" { continue }
            #expect(documented[key]?.en == entry.en, "\(key) en")
            #expect(documented[key]?.ko == entry.ko, "\(key) ko")
        }
    }

    @Test func koreanCopyAvoidsKnownMistakes() {
        for (key, entry) in StringTable.entries {
            #expect(!entry.ko.contains("녹화"), "\(key): 녹화 means video recording")
            #expect(!entry.ko.contains("  ") && !entry.en.contains("  "), "\(key): double space")
            #expect(entry.ko == entry.ko.trimmingCharacters(in: .whitespaces), "\(key)")
            #expect(entry.en == entry.en.trimmingCharacters(in: .whitespaces), "\(key)")
        }
        // Tag and filter removal use the same verb.
        #expect(StringTable.entries["removeTag"]?.ko == "제거" && StringTable.entries["removeFilter"]?.ko == "필터 제거")
    }

    @MainActor @Test func theSavePopupWindowHasATitleForVoiceOver() throws {
        _ = NSApplication.shared
        let controller = SavePopupWindowController()
        let draft = CaptureDraft(type: .text, title: "T", text: "hello", source: DropSource(appName: "Notes"))
        controller.show(SavePopupModel(draft: draft, recentTags: [], save: { _ in throw CancellationError() }, onSaved: { _ in }, onCancel: {}))
        let window = try #require(controller.window)
        #expect(Self.isText(window.title, ofKey: "saveText"))
        controller.close()
    }
}
