import Testing
@testable import PlopcutCore

// R-03: automatic format detection and the user's choice (spec 2.6, PLO-101).

private func detect(_ text: String, app: String? = nil) -> ResolvedFormat {
    FormatDetection.detect(text: text, source: DropSource(appName: app))
}

@Suite struct FormatDetectionTests {
    @Test(arguments: [
        ("Terminal", ResolvedFormat.code(language: "shell")),
        ("터미널", .code(language: "shell")),
        ("iTerm2", .code(language: "shell")),
        ("iTerm", .code(language: "shell")),
        ("Xcode", .code(language: "swift")),
    ])
    func terminalAndXcodeTextIsCode(app: String, expected: ResolvedFormat) {
        // Even text that would otherwise read as Markdown or prose.
        #expect(detect("# Title\n- item", app: app) == expected)
        #expect(detect("ls -la", app: app) == expected)
    }

    @Test(arguments: [
        "{\"a\": 1, \"b\": [true, null]}",
        "  [1, 2, 3]\n",
        "{\n  \"name\": \"plopcut\"\n}",
    ])
    func validJSONObjectOrArrayIsJSONCode(text: String) {
        #expect(detect(text, app: "Notes") == .code(language: "json"))
    }

    @Test(arguments: ["{not json}", "\"just a string\"", "42", "[1, 2", "{}garbage"])
    func otherJSONLookalikesAreNotJSON(text: String) {
        #expect(detect(text) != .code(language: "json"))
    }

    @Test(arguments: [
        "# Title\n\nA paragraph with **bold** text.",
        "Intro\n\n```swift\nlet a = 1\n```",
        "See [the docs](https://example.com) for more.",
        "## Steps\n- one\n- two",
        "> quoted\n\n- a list item",
        "Use `git status` and **commit** often.",
        "1. first\n2. second\n\n**Note:** done",
    ])
    func clearMarkdownSignalsAreMarkdown(text: String) {
        #expect(detect(text, app: "Notes") == .markdown)
    }

    @Test(arguments: [
        "Meeting at 3pm. Bring the #2 pencil and 5 * 3 copies.",
        "I *really* liked it.",
        "# of attendees: 12",
        "- just one bullet",
        "Price: $5 * qty\nTotal # pending",
        "Ordinary sentence.\nAnother line of prose.",
        "",
        "```\nunclosed fence",
    ])
    func proseWithStraySymbolsStaysPlain(text: String) {
        #expect(detect(text, app: "Safari") == .plain)
    }

    @Test func userChoiceWinsOverDetection() {
        let terminal = DropSource(appName: "Terminal")
        #expect(FormatDetection.resolve(text: "ls", source: terminal, format: .markdown, codeLanguage: nil) == .markdown)
        #expect(FormatDetection.resolve(text: "# T\n- a", source: DropSource(), format: .plain, codeLanguage: nil) == .plain)
        #expect(FormatDetection.resolve(text: "x", source: DropSource(), format: .code, codeLanguage: "python") == .code(language: "python"))
        #expect(FormatDetection.resolve(text: "x", source: DropSource(), format: .code, codeLanguage: nil) == .code(language: nil))
        #expect(FormatDetection.resolve(text: "ls", source: terminal, format: nil, codeLanguage: nil) == .code(language: "shell"))
    }

    @Test func resolvesADropFromItsStoredChoice() {
        var drop = Drop(id: "a", type: .text, title: "t", text: "# T\n- a", createdAt: "x", updatedAt: "x")
        #expect(FormatDetection.resolve(drop) == .markdown)
        drop.format = .plain
        #expect(FormatDetection.resolve(drop) == .plain)
    }
}
