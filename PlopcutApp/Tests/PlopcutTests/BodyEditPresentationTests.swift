import AppKit
import Foundation
import PlopcutCore
import SwiftUI
import Testing
@testable import Plopcut

/// The Edit action, its shortcuts, and the dimmed Markdown symbols of the content editor (spec 2.6, PLO-104).
@MainActor
@Suite struct BodyEditPresentationTests {
    // E-07
    @Test func editSitsAfterPinWithCommandE() {
        L10n.languageOverride = "ko"
        defer { L10n.languageOverride = nil }
        #expect(DropAction.editBody.title == "편집")
        #expect(DropAction.editBody.tooltip == "편집 (⌘E)")
        #expect(DropAction.editBody.systemImage == "pencil")
        #expect(DropAction.editBody.shortcut == EditBodyCommand.shortcut)
    }

    // Cmd+E, Cmd+Return and Escape must not clash with the other shortcuts (spec 2.6).
    @Test func editShortcutsDoNotClash() {
        #expect(EditBodyCommand.shortcut.key == "e" && EditBodyCommand.shortcut.modifiers == .command)
        #expect(BodyEditorShortcuts.done.key == .return && BodyEditorShortcuts.done.modifiers == .command)
        let others = [PinCommand.shortcut, RefreshCommand.shortcut, KeyboardShortcut(.delete, modifiers: .command),
                      KeyboardShortcut("f", modifiers: .command)]
        for shortcut in [EditBodyCommand.shortcut, BodyEditorShortcuts.done] { #expect(!others.contains(shortcut)) }
    }

    private func dimmed(_ text: String) -> [String] {
        let string = text as NSString
        return MarkdownSymbols.dimmedRanges(in: text).map { string.substring(with: $0) }
    }

    // E-13: headings, list markers, quotes, fences, emphasis and inline code markers are dimmed.
    @Test func blockMarkersAreDimmed() {
        #expect(dimmed("## Title") == ["##"])
        #expect(dimmed("- item\n* two\n+ three\n12. four") == ["-", "*", "+", "12."])
        #expect(dimmed("> quoted") == [">"])
        #expect(dimmed("  - nested") == ["-"])
    }

    @Test func inlineMarkersAreDimmed() {
        #expect(dimmed("a **bold** b") == ["**", "**"])
        #expect(dimmed("__bold__ and _it_ and *it*") == ["__", "__", "_", "_", "*", "*"])
        #expect(dimmed("~~gone~~") == ["~~", "~~"])
        #expect(dimmed("use `overlay` here") == ["`", "`"])
    }

    @Test func fenceLinesAreDimmedAndTheirContentIsNot() {
        #expect(dimmed("```swift\nlet a = **b**\n# not a heading\n```") == ["```swift", "```"])
        #expect(dimmed("`a **b**`") == ["`", "`"])
    }

    // Plain text with a stray `*` or `#` stays undimmed.
    @Test func plainTextIsLeftAlone() {
        #expect(dimmed("3 * 4 = 12") == [])
        #expect(dimmed("#hashtag and snake_case_name") == [])
        #expect(dimmed("") == [])
    }

    // Ranges are UTF-16, so Hangul and emoji before a marker keep the marker in place.
    @Test func rangesAreUTF16() {
        #expect(dimmed("한글 😀 **굵게**") == ["**", "**"])
    }
}
