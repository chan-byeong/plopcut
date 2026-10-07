import Foundation
import Testing
@testable import NotedropCore

@Suite struct MarkdownTests {
    @Test func fullTextDrop() {
        let drop = Drop(
            id: "1", type: .text, title: "Markdown Title", text: "  Body text \n",
            source: DropSource(appName: "Chrome", windowTitle: "Article", url: "https://example.com", filePath: nil),
            note: "Remember this\n", tags: ["research", "quote"],
            createdAt: "2026-01-01T00:00:00.000000000Z", updatedAt: "2026-01-02T00:00:00.000000000Z")
        #expect(MarkdownExport.render(drop) == """
        # Markdown Title

        ## Metadata

        - Type: text
        - Created: 2026-01-01T00:00:00.000000000Z
        - Updated: 2026-01-02T00:00:00.000000000Z
        - Tags: research, quote
        - App: Chrome
        - Window: Article
        - URL: https://example.com

        ## Text

        Body text

        ## Note

        Remember this

        """)
    }

    @Test func minimalImageDropOmitsEmptySections() {
        let drop = Drop(id: "2", type: .image, title: "Pic", imagePath: "image.png", note: "  ",
                        createdAt: "c", updatedAt: "u")
        #expect(MarkdownExport.render(drop) == "# Pic\n\n## Metadata\n\n- Type: image\n- Created: c\n- Updated: u\n")
    }

    @Test func defaultFileName() {
        #expect(MarkdownExport.fileName(for: Drop(id: "1", type: .text, title: "Hello World", createdAt: "", updatedAt: "")) == "hello-world.md")
        #expect(MarkdownExport.fileName(for: Drop(id: "1", type: .text, title: "한글", createdAt: "", updatedAt: "")) == "drop.md")
    }
}
