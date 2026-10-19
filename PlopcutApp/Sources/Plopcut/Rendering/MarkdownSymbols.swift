import Foundation

/// The Markdown symbols the content editor draws dimmed (spec 2.6 "본문 편집", E-13): heading `#`s, list markers,
/// quote `>`, whole fence lines, emphasis markers and inline code backticks. Display only; the text is never changed.
/// Ranges are UTF-16 (`NSRange`) for the text view. Fenced code content and inline code content are left alone.
enum MarkdownSymbols {
    private static let fence = regex(#"^ {0,3}(`{3,}|~{3,}).*$"#)
    private static let blockMarker = regex(#"^[ \t]*(#{1,6}(?=[ \t])|[-*+](?=[ \t])|\d{1,9}[.)](?=[ \t])|>)"#)
    private static let inlineCode = regex(#"(`+)[^`](?:.*?[^`])?\1(?!`)"#)
    private static let emphasis: [NSRegularExpression] = [
        regex(#"(\*\*|__)(?=\S)(?:.+?)(?<=\S)\1"#),
        regex(#"(~~)(?=\S)(?:.+?)(?<=\S)~~"#),
        regex(#"(?<![*\w])(\*)(?=[^\s*])(?:.*?[^\s*])?\*(?![*\w])"#),
        regex(#"(?<![_\w])(_)(?=[^\s_])(?:.*?[^\s_])?_(?![_\w])"#),
    ]

    static func dimmedRanges(in text: String) -> [NSRange] {
        let string = text as NSString
        var ranges: [NSRange] = []
        var inFence = false
        var location = 0
        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let contents = contentRange(of: lineRange, in: string)
            let line = string.substring(with: contents)
            if fence.firstMatch(in: line, range: NSRange(location: 0, length: contents.length)) != nil {
                ranges.append(contents)
                inFence.toggle()
            } else if !inFence {
                ranges += lineRanges(line).map { NSRange(location: $0.location + contents.location, length: $0.length) }
            }
            location = NSMaxRange(lineRange)
        }
        return ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
    }

    /// The symbols of one line outside a fence, relative to the line.
    private static func lineRanges(_ line: String) -> [NSRange] {
        let whole = NSRange(location: 0, length: (line as NSString).length)
        var ranges: [NSRange] = []
        if let block = blockMarker.firstMatch(in: line, range: whole) { ranges.append(block.range(at: 1)) }
        // Inline code first: markers inside it are code, not emphasis.
        var claimed: [NSRange] = []
        for match in inlineCode.matches(in: line, range: whole) {
            let ticks = match.range(at: 1).length
            claimed.append(match.range)
            ranges.append(NSRange(location: match.range.location, length: ticks))
            ranges.append(NSRange(location: NSMaxRange(match.range) - ticks, length: ticks))
        }
        claimed += ranges
        for pattern in emphasis {
            for match in pattern.matches(in: line, range: whole)
            where !claimed.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                let width = match.range(at: 1).length
                ranges.append(NSRange(location: match.range.location, length: width))
                ranges.append(NSRange(location: NSMaxRange(match.range) - width, length: width))
                claimed.append(match.range)
            }
        }
        return ranges
    }

    /// The line without its line break.
    private static func contentRange(of lineRange: NSRange, in string: NSString) -> NSRange {
        var end = NSMaxRange(lineRange)
        while end > lineRange.location, let scalar = UnicodeScalar(string.character(at: end - 1)),
              CharacterSet.newlines.contains(scalar) { end -= 1 }
        return NSRange(location: lineRange.location, length: end - lineRange.location)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants; a broken one is a programming error the tests catch.
        try! NSRegularExpression(pattern: pattern, options: [])
    }
}
