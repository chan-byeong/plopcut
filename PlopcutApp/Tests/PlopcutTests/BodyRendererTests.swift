import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

// R-04, R-07: what the body shows for each format (spec 2.6, PLO-101).
@Suite struct BodyRendererTests {
    private func markdown(_ text: String) -> [RenderedBlock] { BodyRenderer.blocks(for: text, format: .markdown) }

    private func plain(_ text: AttributedString) -> String { String(text.characters) }

    @Test func plainTextIsShownAsIs() {
        let text = "# not a heading\n**not bold**"
        #expect(BodyRenderer.blocks(for: text, format: .plain) == [.plainText(text)])
    }

    @Test func codeFormatIsOneCodeBlock() {
        let blocks = BodyRenderer.blocks(for: "ls -la\npwd", format: .code(language: "shell"))
        #expect(blocks == [.code(CodeBlockContent(language: "shell", code: "ls -la\npwd"))])
    }

    @Test func headingsKeepTheirLevel() {
        let blocks = markdown("# One\n\n### Three")
        guard case .heading(1, let one) = blocks.first, case .heading(3, let three) = blocks.last else {
            Issue.record("\(blocks)"); return
        }
        #expect(plain(one) == "One" && plain(three) == "Three")
    }

    @Test func inlineStylesBecomePresentationIntents() throws {
        guard case .paragraph(let text) = markdown("a **b** *c* `d`").first else { Issue.record("not a paragraph"); return }
        #expect(plain(text) == "a b c d")
        let intents = text.runs.compactMap { run -> (String, InlinePresentationIntent)? in
            run.inlinePresentationIntent.map { (String(text[run.range].characters), $0) }
        }
        #expect(intents.contains { $0.0 == "b" && $0.1.contains(.stronglyEmphasized) })
        #expect(intents.contains { $0.0 == "c" && $0.1.contains(.emphasized) })
        #expect(intents.contains { $0.0 == "d" && $0.1.contains(.code) })
    }

    @Test func nestedListsKeepStructureAndMarkers() {
        let blocks = markdown("- one\n  - inner\n- two\n\n3. three\n4. four")
        guard case .list(let bullets) = blocks.first, case .list(let numbers) = blocks.last else {
            Issue.record("\(blocks)"); return
        }
        #expect(bullets.items.map(\.marker) == ["•", "•"])
        guard case .list(let inner)? = bullets.items.first?.blocks.last else { Issue.record("no nested list"); return }
        #expect(inner.items.count == 1)
        #expect(inner.depth == 1)
        #expect(numbers.items.map(\.marker) == ["3.", "4."])
    }

    @Test func taskItemsShowTheirCheckbox() {
        guard case .list(let list) = markdown("- [ ] todo\n- [x] done").first else { Issue.record("no list"); return }
        #expect(list.items.map(\.marker) == ["☐", "☑"])
    }

    @Test func quotesRulesAndFencedCode() {
        let blocks = markdown("> quoted\n\n---\n\n```swift\nlet a = 1\n```")
        guard blocks.count == 3, case .quote(let inner) = blocks[0] else { Issue.record("\(blocks)"); return }
        #expect(inner.count == 1)
        #expect(blocks[1] == .rule)
        #expect(blocks[2] == .code(CodeBlockContent(language: "swift", code: "let a = 1")))
    }

    @Test func fenceWithoutLanguageHasNone() {
        #expect(markdown("```\nplain\n```") == [.code(CodeBlockContent(language: nil, code: "plain"))])
    }

    @Test func webLinksAreLinksAndOtherSchemesAreText() {
        guard case .paragraph(let text) = markdown("[web](https://example.com) and [file](file:///etc/hosts)").first else {
            Issue.record("not a paragraph"); return
        }
        let links = text.runs.compactMap { $0.link }
        #expect(links == [URL(string: "https://example.com")!])
        #expect(plain(text) == "web and file")
    }

    @Test func imagesAndHTMLStayAsSourceText() {
        let blocks = markdown("![logo](https://example.com/logo.png)\n\n<div>hi</div>")
        guard blocks.count == 2, case .paragraph(let image) = blocks[0] else { Issue.record("\(blocks)"); return }
        #expect(plain(image) == "![logo](https://example.com/logo.png)")
        #expect(image.runs.allSatisfy { $0.link == nil })
        #expect(blocks[1] == .source("<div>hi</div>"))
    }

    // PLO-107: GFM tables become rows and columns instead of their source.
    @Test func tablesKeepHeaderRowsAndAlignments() {
        let blocks = markdown("Intro\n\n| Name | Qty | Note |\n| :--- | ---: | :-: |\n| apple | 3 | ok |\n| pear | 10 | |")
        guard blocks.count == 2, case .table(let table) = blocks[1] else { Issue.record("\(blocks)"); return }
        #expect(table.header.map(plain) == ["Name", "Qty", "Note"])
        #expect(table.rows.map { $0.map(plain) } == [["apple", "3", "ok"], ["pear", "10", ""]])
        #expect(table.alignments == [.leading, .trailing, .center])
    }

    @Test func tableCellsKeepInlineStylesAndLinks() {
        guard case .table(let table) = markdown("| a | b |\n| - | - |\n| **bold** `code` | [web](https://example.com) |").first,
              let row = table.rows.first, row.count == 2 else { Issue.record("no table"); return }
        #expect(plain(row[0]) == "bold code")
        #expect(row[0].runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(row[1].runs.compactMap(\.link) == [URL(string: "https://example.com")!])
        #expect(table.alignments == [nil, nil])
    }

    @Test func shortTableRowsArePaddedToTheHeader() {
        guard case .table(let table) = markdown("| a | b | c |\n| - | - | - |\n| 1 |").first else { Issue.record("no table"); return }
        #expect(table.rows.map { $0.map(plain) } == [["1", "", ""]])
    }

    @Test func singleLineBreaksAreKept() {
        guard case .paragraph(let text) = markdown("line one\nline two").first else { Issue.record("not a paragraph"); return }
        #expect(plain(text) == "line one\nline two")
    }
}
