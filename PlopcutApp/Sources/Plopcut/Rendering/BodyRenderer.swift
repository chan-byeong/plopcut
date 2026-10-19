import Foundation
import Markdown
import PlopcutCore

/// A code block's language (as written, e.g. `swift` or `js`) and its code without the trailing newline.
struct CodeBlockContent: Equatable, Hashable, Sendable {
    var language: String?
    var code: String
}

struct RenderedList: Equatable, Hashable, Sendable {
    struct Item: Equatable, Hashable, Sendable {
        /// `•`/`◦` for bullets, `3.` for numbers, `☐`/`☑` for task items.
        var marker: String
        var blocks: [RenderedBlock]
    }

    var ordered: Bool
    /// 0 for a top-level list.
    var depth: Int
    var items: [Item]
}

/// A body ready to draw: our own Sendable value, because swift-markdown's nodes are not Sendable (spec 2.6, PLO-101).
indirect enum RenderedBlock: Equatable, Hashable, Sendable {
    /// The plain-text format: the original text, untouched.
    case plainText(String)
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case list(RenderedList)
    case quote([RenderedBlock])
    case code(CodeBlockContent)
    case rule
    /// Tables and HTML, shown as their Markdown source.
    case source(String)
}

/// Turns a text body into blocks for its format. Parsing and conversion happen in one synchronous call.
enum BodyRenderer {
    static func blocks(for text: String, format: ResolvedFormat) -> [RenderedBlock] {
        switch format {
        case .plain: return [.plainText(text)]
        case .code(let language): return [.code(CodeBlockContent(language: language, code: text))]
        case .markdown:
            var converter = Converter(lines: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
            return Document(parsing: text).children.compactMap { converter.block($0, depth: 0) }
        }
    }
}

private struct Converter {
    /// The source, so blocks shown as text keep the lines the user wrote.
    let lines: [String]

    mutating func block(_ markup: any Markup, depth: Int) -> RenderedBlock? {
        switch markup {
        case let heading as Heading:
            return .heading(level: heading.level, text: inlines(heading.children))
        case let paragraph as Paragraph:
            return .paragraph(inlines(paragraph.children))
        case let list as UnorderedList:
            let marker = depth == 0 ? "•" : "◦"
            return .list(RenderedList(ordered: false, depth: depth, items: list.listItems.map { item($0, marker: marker, depth: depth) }))
        case let list as OrderedList:
            let start = Int(list.startIndex)
            let items = list.listItems.enumerated().map { index, entry in item(entry, marker: "\(start + index).", depth: depth) }
            return .list(RenderedList(ordered: true, depth: depth, items: items))
        case let quote as BlockQuote:
            return .quote(quote.children.compactMap { block($0, depth: depth) })
        case is ThematicBreak:
            return .rule
        case let code as CodeBlock:
            return .code(CodeBlockContent(language: code.language?.trimmedNonEmpty, code: Self.dropTrailingNewlines(code.code)))
        case let html as HTMLBlock:
            return .source(Self.dropTrailingNewlines(html.rawHTML))
        default:
            // Tables and anything else this renderer does not draw keep their Markdown source.
            return .source(sourceLines(of: markup) ?? Self.dropTrailingNewlines(markup.format()))
        }
    }

    /// Whole source lines of a block. Lines are 1-based; whole lines avoid byte-column offsets in non-ASCII text.
    private func sourceLines(of markup: any Markup) -> String? {
        guard let range = markup.range else { return nil }
        let first = range.lowerBound.line - 1, last = min(range.upperBound.line - 1, lines.count - 1)
        guard first >= 0, first <= last else { return nil }
        return Self.dropTrailingNewlines(lines[first...last].map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }.joined(separator: "\n"))
    }

    private mutating func item(_ item: ListItem, marker: String, depth: Int) -> RenderedList.Item {
        let shown: String = switch item.checkbox {
        case .checked: "☑"
        case .unchecked: "☐"
        case nil: marker
        }
        return RenderedList.Item(marker: shown, blocks: item.children.compactMap { block($0, depth: depth + 1) })
    }

    private func inlines(_ children: MarkupChildren) -> AttributedString {
        children.reduce(into: AttributedString()) { $0 += inline($1, intent: [], link: nil) }
    }

    private func inline(_ markup: any Markup, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
        func styled(_ string: String, _ intent: InlinePresentationIntent) -> AttributedString {
            var piece = AttributedString(string)
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if let link { piece.link = link }
            return piece
        }
        func children(_ intent: InlinePresentationIntent, link: URL?) -> AttributedString {
            markup.children.reduce(into: AttributedString()) { $0 += inline($1, intent: intent, link: link) }
        }
        switch markup {
        case let text as Markdown.Text: return styled(text.string, intent)
        case is SoftBreak, is LineBreak: return styled("\n", intent)
        case let code as InlineCode: return styled(code.code, intent.union(.code))
        case is Emphasis: return children(intent.union(.emphasized), link: link)
        case is Strong: return children(intent.union(.stronglyEmphasized), link: link)
        case is Strikethrough: return children(intent.union(.strikethrough), link: link)
        case let anchor as Markdown.Link:
            // Only web and mail links can be followed; other schemes keep their text (R-07).
            let url = anchor.destination.flatMap(URL.init(string:)).flatMap { LibraryModel.isOpenableLink($0) ? $0 : nil }
            return children(intent, link: url ?? link)
        case let image as Markdown.Image:
            // Never loaded, local or remote: the source text stays visible (spec 2.6).
            return AttributedString(image.format())
        case let html as InlineHTML: return styled(html.rawHTML, intent)
        default: return children(intent, link: link)
        }
    }

    private static func dropTrailingNewlines(_ text: String) -> String {
        var result = Substring(text)
        while result.last?.isNewline == true { result = result.dropLast() }
        return String(result)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
