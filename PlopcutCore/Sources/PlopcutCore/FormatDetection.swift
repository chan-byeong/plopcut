import Foundation

/// How a text drop's body is shown: the user's choice, or what detection picked (spec 2.6, PLO-101).
public enum ResolvedFormat: Equatable, Hashable, Sendable {
    case plain
    case markdown
    /// `language` is a highlight identifier such as `swift`, or `nil` for code without a language.
    case code(language: String?)

    public var dropFormat: DropFormat {
        switch self {
        case .plain: .plain
        case .markdown: .markdown
        case .code: .code
        }
    }
}

/// Picks a text drop's format. Pure, so the rules are fixed by `FormatDetectionTests`.
public enum FormatDetection {
    /// Languages offered in the format menu, as stored in `codeLanguage`.
    public static let codeLanguages = ["swift", "shell", "json", "javascript", "typescript", "python"]

    /// Shell for terminals, Swift for Xcode. Matched case-insensitively against the app name, including the Korean name.
    private static let codeApps: [String: String] = [
        "terminal": "shell", "터미널": "shell", "iterm": "shell", "iterm2": "shell", "xcode": "swift",
    ]

    public static func resolve(_ drop: Drop) -> ResolvedFormat {
        resolve(text: drop.text ?? "", source: drop.source, format: drop.format, codeLanguage: drop.codeLanguage)
    }

    /// The stored choice when there is one, otherwise `detect`.
    public static func resolve(text: String, source: DropSource, format: DropFormat?, codeLanguage: String?) -> ResolvedFormat {
        switch format {
        case .plain: .plain
        case .markdown: .markdown
        case .code: .code(language: codeLanguage?.trimmedNonEmpty)
        case nil: detect(text: text, source: source)
        }
    }

    /// Terminal and Xcode text is code, a whole JSON object or array is JSON, clear Markdown signals are Markdown,
    /// and everything else, including prose with a stray `*` or `#`, is plain.
    public static func detect(text: String, source: DropSource) -> ResolvedFormat {
        if let app = source.appName?.trimmingCharacters(in: .whitespaces).lowercased(), let language = codeApps[app] {
            return .code(language: language)
        }
        if isJSONContainer(text) { return .code(language: "json") }
        return hasClearMarkdownSignals(text) ? .markdown : .plain
    }

    private static func isJSONContainer(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        guard let value = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else { return false }
        return value is [String: Any] || value is [Any]
    }

    private enum Signal: CaseIterable { case heading, list, quote, strong, inlineCode }

    private static func hasClearMarkdownSignals(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
        if hasClosedFence(lines) || hasTable(lines) { return true }
        if text.contains(/\[[^\]\n]+\]\([^)\s]+\)/) { return true }

        var signals = Set<Signal>()
        for line in lines {
            if line.wholeMatch(of: /#{1,6}[ \t]+\S.*/) != nil { signals.insert(.heading) }
            if line.wholeMatch(of: /[ \t]*([-*+]|\d{1,9}[.)])[ \t]+\S.*/) != nil { signals.insert(.list) }
            if line.wholeMatch(of: /[ \t]{0,3}>[ \t]?\S.*/) != nil { signals.insert(.quote) }
        }
        if text.contains(/\*\*[^*\n]+\*\*|__[^_\n]+__/) { signals.insert(.strong) }
        if text.contains(/`[^`\n]+`/) { signals.insert(.inlineCode) }
        return signals.count >= 2
    }

    /// A header row with a `|` directly followed by a delimiter row (`| --- | :-: |`) with as many cells (GFM table, PLO-107).
    private static func hasTable(_ lines: [Substring]) -> Bool {
        zip(lines, lines.dropFirst()).contains { header, delimiter in
            header.contains("|") && delimiter.contains("|")
                && delimiter.wholeMatch(of: /[ \t]{0,3}\|?([ \t]*:?-+:?[ \t]*\|)*[ \t]*:?-+:?[ \t]*\|?[ \t]*/) != nil
                && tableCells(header) == tableCells(delimiter)
        }
    }

    /// Cells of a table row: `|`-separated, ignoring one leading and one trailing `|`.
    private static func tableCells(_ line: Substring) -> Int {
        var row = line.trimmingCharacters(in: .whitespaces)[...]
        if row.hasPrefix("|") { row = row.dropFirst() }
        if row.hasSuffix("|") { row = row.dropLast() }
        return row.split(separator: "|", omittingEmptySubsequences: false).count
    }

    /// A ``` or ~~~ line followed later by a closing line with the same fence.
    private static func hasClosedFence(_ lines: [Substring]) -> Bool {
        var open: String?
        for line in lines {
            let trimmed = line.drop { $0 == " " }
            for fence in ["```", "~~~"] where trimmed.hasPrefix(fence) {
                if let current = open {
                    if current == fence, trimmed.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == fence.first }) { return true }
                } else {
                    open = fence
                }
            }
        }
        return false
    }
}
