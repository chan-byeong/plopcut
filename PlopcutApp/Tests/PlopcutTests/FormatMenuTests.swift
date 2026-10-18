import AppKit
import PlopcutCore
import Testing
@testable import Plopcut

// R-05, R-08: format button names, menu choices and the code copy button (spec 2.6, PLO-101).
@MainActor
@Suite struct FormatMenuTests {
    @Test func buttonNamesTheResolvedFormat() {
        L10n.languageOverride = "ko"
        defer { L10n.languageOverride = nil }
        #expect(FormatMenu.name(for: .plain) == "일반 텍스트")
        #expect(FormatMenu.name(for: .markdown) == "Markdown")
        #expect(FormatMenu.name(for: .code(language: "swift")) == "Swift")
        #expect(FormatMenu.name(for: .code(language: nil)) == "코드")
    }

    @Test func automaticItemShowsWhatDetectionPicked() {
        L10n.languageOverride = "ko"
        defer { L10n.languageOverride = nil }
        let drop = Drop(id: "a", type: .text, title: "t", text: "ls", source: DropSource(appName: "Terminal"),
                        createdAt: "x", updatedAt: "x", format: .plain)
        #expect(FormatMenu.automaticTitle(for: drop) == "자동 감지 (Shell)")
    }

    @Test func checkedChoiceFollowsTheStoredValue() {
        var drop = Drop(id: "a", type: .text, title: "t", text: "x", createdAt: "x", updatedAt: "x")
        #expect(FormatMenu.isChecked(.automatic, drop: drop))
        #expect(!FormatMenu.isChecked(.set(.plain, codeLanguage: nil), drop: drop))
        drop.format = .code; drop.codeLanguage = "python"
        #expect(FormatMenu.isChecked(.set(.code, codeLanguage: "python"), drop: drop))
        #expect(!FormatMenu.isChecked(.set(.code, codeLanguage: "swift"), drop: drop))
        #expect(!FormatMenu.isChecked(.automatic, drop: drop))
    }

    @Test func copyButtonWritesOnlyTheCode() {
        let board = NSPasteboard(name: NSPasteboard.Name("plopcut-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("old", forType: .string)
        CodeBlockView.copy("let a = 1", to: board)
        #expect(board.string(forType: .string) == "let a = 1")
    }
}
