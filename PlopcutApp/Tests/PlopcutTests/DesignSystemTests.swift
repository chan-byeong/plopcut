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

