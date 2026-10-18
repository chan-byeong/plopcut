import AppKit
import Highlighter
import SwiftUI

/// Code language names: identifiers stored in `codeLanguage`, fence names, and what the UI shows.
enum CodeLanguage {
    /// Fence names that highlight.js knows under another name. `shell` in highlight.js is a console-session grammar.
    private static let highlightNames: [String: String] = ["shell": "bash", "sh": "bash", "zsh": "bash", "console": "bash"]

    private static let displayNames: [String: String] = [
        "swift": "Swift", "shell": "Shell", "bash": "Shell", "sh": "Shell", "zsh": "Shell",
        "json": "JSON", "javascript": "JavaScript", "js": "JavaScript", "typescript": "TypeScript", "ts": "TypeScript",
        "python": "Python", "py": "Python",
    ]

    static func highlightName(for language: String) -> String {
        let key = language.lowercased()
        return highlightNames[key] ?? key
    }

    /// A proper name for known languages, otherwise the name as written.
    static func displayName(for language: String) -> String {
        displayNames[language.lowercased()] ?? language
    }
}

/// Highlights code with HighlighterSwift (highlight.js bundled in the app, no network) using the library's
/// `github` and `github-dark` themes as they are (spec 2.6). Not Sendable, so it lives on the main actor.
@MainActor
final class CodeHighlighter {
    static let shared = CodeHighlighter()

    private lazy var light = Self.make(theme: "github")
    private lazy var dark = Self.make(theme: "github-dark")
    private lazy var supported: Set<String> = Set((light ?? dark)?.supportedLanguages() ?? [])
    /// Switching between drops re-renders the same blocks; keep recent results (spec 2.6, user story 22).
    private var cache: [Key: AttributedString] = [:]
    private var order: [Key] = []
    private static let cacheLimit = 64

    private struct Key: Hashable { let code: String, language: String, dark: Bool }

    private static func make(theme: String) -> Highlighter? {
        guard let highlighter = Highlighter() else { return nil }
        _ = highlighter.setTheme(theme)
        return highlighter
    }

    /// Colored code, or `nil` when there is no language or highlight.js does not know it (shown uncolored then).
    func highlight(_ code: String, language: String?, dark isDark: Bool) -> AttributedString? {
        guard let language else { return nil }
        let name = CodeLanguage.highlightName(for: language)
        let key = Key(code: code, language: name, dark: isDark)
        if let cached = cache[key] { return cached }
        guard supported.contains(name) || Self.isAlias(name),
              let output = (isDark ? dark : light)?.highlight(code, as: name) else { return nil }
        let result = Self.colorsOnly(output)
        guard String(result.characters) == code else { return nil }
        cache[key] = result
        order.append(key)
        if order.count > Self.cacheLimit { cache[order.removeFirst()] = nil }
        return result
    }

    /// highlight.js also accepts aliases (`js`, `py`) that `supportedLanguages()` does not list.
    private static func isAlias(_ name: String) -> Bool { ["js", "ts", "py", "bash"].contains(name) }

    /// Keeps only the foreground colors; the view sets the monospaced font and size.
    private static func colorsOnly(_ source: NSAttributedString) -> AttributedString {
        var result = AttributedString()
        source.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: source.length)) { value, range, _ in
            var piece = AttributedString(source.attributedSubstring(from: range).string)
            if let color = value as? NSColor { piece.foregroundColor = Color(nsColor: color) }
            result += piece
        }
        return result
    }
}
