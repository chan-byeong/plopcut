import AppKit

/// Where a floating panel opens, how big it may get, and when it turns translucent (spec 2.8).
/// Pure functions over plain rectangles, so the rules are tested without a window or a screen.
enum FloatingPanelLayout {
    static let defaultWidth: CGFloat = 300
    static let widthRange: ClosedRange<CGFloat> = 240...420
    /// The smallest content height the user can drag to, below the title bar.
    static let minContentHeight: CGFloat = 120
    /// A panel opens no taller than this share of the screen's visible height; longer content scrolls.
    static let maxHeightShare: CGFloat = 0.6
    /// Gap from the visible area's top right corner to the first panel.
    static let inset: CGFloat = 24
    /// Each further panel opens this much further left and down.
    static let cascadeStep: CGFloat = 24
    /// The panel's opacity while the cursor is elsewhere and the panel does not have the keyboard.
    static let idleOpacity: CGFloat = 0.78
    /// How long the change between translucent and opaque takes, unless Reduce Motion is on.
    static let opacityTransition: TimeInterval = 0.15

    /// The tallest a panel opens: the whole window, title bar included.
    static func maxOpeningHeight(in visible: NSRect) -> CGFloat {
        (visible.height * maxHeightShare).rounded(.down)
    }

    /// The window height for content of `contentHeight` under a title bar of `titleBar`.
    static func openingHeight(contentHeight: CGFloat, titleBar: CGFloat, in visible: NSRect) -> CGFloat {
        let wanted = titleBar + max(contentHeight.rounded(.up), minContentHeight)
        return max(min(wanted, maxOpeningHeight(in: visible)), titleBar + minContentHeight)
    }

    /// The frame of the panel that opens after `cascade` others: top right of the visible area, stepped left and down,
    /// and pulled back inside when the step would leave the screen.
    static func openingFrame(size: NSSize, cascade: Int, in visible: NSRect) -> NSRect {
        let step = CGFloat(cascade) * cascadeStep
        var frame = NSRect(
            x: visible.maxX - inset - size.width - step,
            y: visible.maxY - inset - step - size.height,
            width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    /// Translucent only while the cursor is elsewhere and the user is not typing in it. Reduce Transparency keeps
    /// every panel opaque.
    static func isTranslucent(cursorInside: Bool, isKey: Bool, reduceTransparency: Bool) -> Bool {
        !reduceTransparency && !cursorInside && !isKey
    }
}
