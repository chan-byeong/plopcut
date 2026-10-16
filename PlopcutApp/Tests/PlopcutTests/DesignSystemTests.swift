import Foundation
import CoreGraphics
import PlopcutCore
import Testing
@testable import Plopcut

@Suite struct LayoutTests {
    @Test func sideBySideWidthIsTheSumOfThePanes() {
        #expect(LayoutMetrics.sideBySideWidth == 1176)
        let panes: CGFloat = LayoutMetrics.sidebarDefault + LayoutMetrics.listMin + LayoutMetrics.bodyMin
            + 2 * LayoutMetrics.dividerAllowance + LayoutMetrics.inspectorWidth
        #expect(LayoutMetrics.sideBySideWidth == panes)
    }

    @Test func inspectorSitsBesideTheBodyOnlyWhenItFits() {
        #expect(LayoutMetrics.inspectorFitsBeside(contentWidth: 1176, sidebarHidden: false))
        #expect(!LayoutMetrics.inspectorFitsBeside(contentWidth: 1175, sidebarHidden: false))
        // Hiding the sidebar frees its default width.
        #expect(LayoutMetrics.inspectorFitsBeside(contentWidth: 956, sidebarHidden: true))
        #expect(!LayoutMetrics.inspectorFitsBeside(contentWidth: 955, sidebarHidden: true))
    }

    @Test func searchCollapsesBelowItsThreshold() {
        #expect(LayoutMetrics.searchIsCompact(windowWidth: 1049))
        #expect(!LayoutMetrics.searchIsCompact(windowWidth: 1050))
    }

    @Test func sidebarDefaultMatchesTheStoredDefault() {
        #expect(Double(LayoutMetrics.sidebarDefault) == PaneWidths.default.sidebar)
    }
}

@Suite struct TagInputRuleTests {
    @Test func aTypedCommaRegisters() {
        #expect(TagInputRule.registersOnChange(old: "swif", new: "swift,"))
    }

    @Test func typingWithoutACommaDoesNot() {
        #expect(!TagInputRule.registersOnChange(old: "swif", new: "swift"))
        #expect(!TagInputRule.registersOnChange(old: "a,b", new: "a,bc"))
    }

    @Test func pastedTextWithACommaRegisters() {
        #expect(TagInputRule.registersOnChange(old: "", new: "a, b"))
    }

    @Test func aCommaLeftInsideByACompositionCommitDoesNot() {
        // The commit inserts the syllable before an existing comma; only one character arrives at a time.
        #expect(!TagInputRule.registersOnChange(old: "가,", new: "가,나"))
    }
}


@Suite struct BrandColorTests {
    /// sRGB components (0…1) of each appearance in the AccentColor asset; `nil` is the default (light) entry.
    static func accentColors() throws -> [String?: [Double]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Assets.xcassets/AccentColor.colorset/Contents.json")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var result: [String?: [Double]] = [:]
        for entry in try #require(json["colors"] as? [[String: Any]]) {
            let appearance = (entry["appearances"] as? [[String: String]])?.first?["value"]
            let components = try #require((entry["color"] as? [String: Any])?["components"] as? [String: String])
            result[appearance] = try ["red", "green", "blue"].map { key in
                let hex = try #require(components[key])
                return Double(try #require(Int(hex.dropFirst(2), radix: 16))) / 255
            }
        }
        return result
    }

    // U-02: light #2F6BFF, dark #4F8CFF (spec 5).
    @Test func accentAssetMatchesTheSpec() throws {
        let colors = try Self.accentColors()
        #expect(colors[nil] == [0x2F, 0x6B, 0xFF].map { Double($0) / 255 })
        #expect(colors["dark"] == [0x4F, 0x8C, 0xFF].map { Double($0) / 255 })
    }

}

@Suite struct TagDisplayTests {
    // U-04: shown with #, stored without.
    @Test func tagsAreShownWithAHash() {
        #expect(Formatting.tag("design") == "#design")
        #expect(Formatting.tag("two words") == "#two words")
    }
}
