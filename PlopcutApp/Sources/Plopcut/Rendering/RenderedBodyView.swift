import AppKit
import PlopcutCore
import SwiftUI

/// Recent render results, so switching between drops does not parse the same body again (spec 2.6, user story 22).
@MainActor
enum BodyRenderCache {
    private struct Key: Hashable { let text: String, format: ResolvedFormat }
    private static var entries: [Key: [RenderedBlock]] = [:]
    private static var order: [Key] = []
    private static let limit = 32

    static func blocks(for text: String, format: ResolvedFormat) -> [RenderedBlock] {
        let key = Key(text: text, format: format)
        if let hit = entries[key] { return hit }
        let blocks = BodyRenderer.blocks(for: text, format: format)
        entries[key] = blocks
        order.append(key)
        if order.count > limit { entries[order.removeFirst()] = nil }
        return blocks
    }
}

/// A text body drawn for its format (spec 2.6). Text stays selectable; links go through `openLink`.
struct RenderedBodyView: View {
    let text: String
    let format: ResolvedFormat
    var openLink: (URL) -> Void

    var body: some View {
        BlockStack(blocks: BodyRenderCache.blocks(for: text, format: format))
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                openLink(url)
                return .handled
            })
    }
}

private struct BlockStack: View {
    let blocks: [RenderedBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockView: View {
    let block: RenderedBlock

    var body: some View {
        switch block {
        case .plainText(let text):
            Text(text).font(.body)
        case .heading(let level, let text):
            Text(text).font(Self.headingFont(level))
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(Self.headingLevel(level))
        case .paragraph(let text):
            Text(text).font(.body)
        case .list(let list):
            ListBlockView(list: list)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: Spacing.s) {
                RoundedRectangle(cornerRadius: 1.5).fill(.tertiary).frame(width: 3)
                BlockStack(blocks: blocks).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.t("markdownQuote"))
        case .code(let content):
            CodeBlockView(content: content)
        case .rule:
            Divider()
        case .source(let text):
            Text(text).font(.body.monospaced())
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }

    private static func headingLevel(_ level: Int) -> AccessibilityHeadingLevel {
        switch level {
        case 1: .h1
        case 2: .h2
        case 3: .h3
        case 4: .h4
        case 5: .h5
        default: .h6
        }
    }
}

private struct ListBlockView: View {
    let list: RenderedList

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(item.marker).monospacedDigit().foregroundStyle(.secondary)
                    BlockStack(blocks: item.blocks)
                }
                // Read as one item, marker first ("1. first", "• item").
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("markdownList"))
    }
}

/// A code block: language name and copy button over monospaced, highlighted code (spec 2.6, R-05).
struct CodeBlockView: View {
    let content: CodeBlockContent
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    private var languageName: String {
        content.language.map(CodeLanguage.displayName(for:)) ?? L10n.t("formatCode")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(languageName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Self.copy(content.code, to: .general)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(L10n.t("copyCode"))
                .accessibilityLabel(L10n.t("copyCode"))
            }
            .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
            Divider()
            ScrollView(.horizontal) {
                code.font(.system(.callout, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(Spacing.s)
            }
            .slimScrollers()
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).stroke(.separator, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("codeBlock", ["language": languageName]))
    }

    private var code: Text {
        if let highlighted = CodeHighlighter.shared.highlight(content.code, language: content.language, dark: colorScheme == .dark) {
            return Text(highlighted)
        }
        return Text(content.code)
    }

    /// Copies only the block's code (no fence, no trailing newline).
    static func copy(_ code: String, to board: NSPasteboard) {
        board.clearContents()
        board.setString(code, forType: .string)
    }
}

/// Names and choices of the format button and menu (spec 2.6, R-08).
enum FormatMenu {
    static func name(for format: ResolvedFormat) -> String {
        switch format {
        case .plain: L10n.t("formatPlain")
        case .markdown: L10n.t("formatMarkdown")
        case .code(let language): language.map(CodeLanguage.displayName(for:)) ?? L10n.t("formatCode")
        }
    }

    /// `자동 감지 (Shell)`: what the drop would show without a stored choice.
    static func automaticTitle(for drop: Drop) -> String {
        let detected = FormatDetection.detect(text: drop.text ?? "", source: drop.source)
        return L10n.t("formatAutomatic", ["format": name(for: detected)])
    }

    static func isChecked(_ choice: FormatUpdate, drop: Drop) -> Bool {
        switch choice {
        case .automatic: drop.format == nil
        case .set(let format, let language): drop.format == format && (format != .code || drop.codeLanguage == language)
        }
    }
}

/// `Markdown ▾` beside the type label of a text drop.
struct FormatMenuButton: View {
    let drop: Drop
    var choose: (FormatUpdate) -> Void

    var body: some View {
        let current = FormatMenu.name(for: FormatDetection.resolve(drop))
        Menu {
            item(FormatMenu.automaticTitle(for: drop), .automatic)
            Divider()
            item(L10n.t("formatPlain"), .set(.plain, codeLanguage: nil))
            item(L10n.t("formatMarkdown"), .set(.markdown, codeLanguage: nil))
            Menu(L10n.t("formatCode")) {
                ForEach(FormatDetection.codeLanguages, id: \.self) { language in
                    item(CodeLanguage.displayName(for: language), .set(.code, codeLanguage: language))
                }
            }
        } label: {
            Text(current).font(.caption)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help(L10n.t("formatMenuHelp"))
        .accessibilityLabel(L10n.t("formatMenu", ["format": current]))
    }

    private func item(_ title: String, _ choice: FormatUpdate) -> some View {
        Toggle(title, isOn: Binding(get: { FormatMenu.isChecked(choice, drop: drop) }, set: { _ in choose(choice) }))
    }
}

/// The detected format's name as a small badge (Save Popup preview, spec 3.5).
struct FormatBadge: View {
    let format: ResolvedFormat

    var body: some View {
        Text(FormatMenu.name(for: format))
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.xs).padding(.vertical, Spacing.xxs)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(L10n.t("formatMenu", ["format": FormatMenu.name(for: format)]))
    }
}
