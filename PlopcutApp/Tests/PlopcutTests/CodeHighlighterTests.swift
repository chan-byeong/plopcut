import SwiftUI
import Testing
@testable import Plopcut

// R-05: offline syntax highlighting with the library's light and dark themes (spec 2.6, PLO-101).
@MainActor
@Suite struct CodeHighlighterTests {
    private let swiftCode = "let greeting = \"hi\" // say hello\nfunc f() -> Int { 42 }"

    private func colors(_ text: AttributedString) -> Set<Color> {
        Set(text.runs.compactMap { $0.foregroundColor })
    }

    @Test func swiftGetsSeveralColorsAndKeepsTheText() throws {
        let highlighted = try #require(CodeHighlighter.shared.highlight(swiftCode, language: "swift", dark: false))
        #expect(String(highlighted.characters) == swiftCode)
        #expect(colors(highlighted).count >= 3)
    }

    @Test func darkAndLightUseDifferentColors() throws {
        let light = try #require(CodeHighlighter.shared.highlight(swiftCode, language: "swift", dark: false))
        let dark = try #require(CodeHighlighter.shared.highlight(swiftCode, language: "swift", dark: true))
        #expect(colors(light) != colors(dark))
    }

    @Test(arguments: ["swift", "shell", "json", "javascript", "typescript", "python", "js", "sh", "py"])
    func menuLanguagesAndCommonFenceNamesHighlight(language: String) throws {
        let sample = "x = [1, \"two\", true] # done"
        let highlighted = try #require(CodeHighlighter.shared.highlight(sample, language: language, dark: false))
        #expect(String(highlighted.characters) == sample)
    }

    @Test func unknownOrMissingLanguageIsNotHighlighted() {
        #expect(CodeHighlighter.shared.highlight("x", language: "nosuchlanguage", dark: false) == nil)
        #expect(CodeHighlighter.shared.highlight("x", language: nil, dark: false) == nil)
    }

    @Test(arguments: [("swift", "Swift"), ("shell", "Shell"), ("sh", "Shell"), ("js", "JavaScript"), ("json", "JSON"), ("rust", "rust")])
    func displayNames(id: String, name: String) {
        #expect(CodeLanguage.displayName(for: id) == name)
    }
}
