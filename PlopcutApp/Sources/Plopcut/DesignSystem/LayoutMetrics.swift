import CoreGraphics
import PlopcutCore

/// Window and pane sizes (design-system.md, "레이아웃"). Pane widths and their ranges come from `PaneWidths`, which
/// owns the stored defaults; everything that decides where a pane goes is computed here from these numbers.
enum LayoutMetrics {
    static let sidebarDefault = CGFloat(PaneWidths.default.sidebar)
    static let sidebarRange = CGFloat(PaneWidths.sidebarRange.lowerBound)...CGFloat(PaneWidths.sidebarRange.upperBound)
    static let listRange = CGFloat(PaneWidths.libraryRange.lowerBound)...CGFloat(PaneWidths.libraryRange.upperBound)
    static var listMin: CGFloat { listRange.lowerBound }
    /// The inspector is a fixed column, beside the body or as an overlay.
    static let inspectorWidth: CGFloat = 280
    static let bodyMin: CGFloat = 360
    /// What each of the two pane dividers takes in the side-by-side sum.
    static let dividerAllowance: CGFloat = 8
    /// The narrowest content that fits sidebar, list, body, both dividers and the inspector side by side.
    static let sideBySideWidth = sidebarDefault + listMin + bodyMin + 2 * dividerAllowance + inspectorWidth
    /// Below this window width the toolbar search field collapses to an icon.
    static let compactSearchWidth: CGFloat = 1050
    static let windowMin = CGSize(width: 960, height: 640)
    static let windowDefault = CGSize(width: 1120, height: 720)
    /// Popovers that hold a small form, such as the filters.
    static let popoverWidth: CGFloat = 280

    static func inspectorFitsBeside(contentWidth: CGFloat, sidebarHidden: Bool) -> Bool {
        contentWidth >= sideBySideWidth - (sidebarHidden ? sidebarDefault : 0)
    }

    static func searchIsCompact(windowWidth: CGFloat) -> Bool { windowWidth < compactSearchWidth }
}

/// Corner radii the app draws itself. Standard controls keep the system's shapes.
enum Radius {
    /// Input surfaces and content wells: an editable title, the note, the popup preview, the shortcut field.
    static let field: CGFloat = 6
    /// A source app icon in a list row.
    static let appIcon: CGFloat = 4
}
