import AppKit
import SwiftUI

/// Thinner vertical scroll bars for the app's text areas and lists (STA-68).
///
/// AppKit draws a legacy scroll bar 17 pt wide and a small one 13 pt wide, with a thinner knob. The helper only sets
/// the scroller's control size; the scroller style (legacy or overlay), auto-hiding and dragging stay with the
/// system's "Show scroll bars" setting. Overlay scroll bars are already thin and appear only while scrolling.
enum SlimScroller {
    /// `.mini` gives the same width as `.small` for a vertical scroller, so the standard small size is used.
    static let controlSize = NSControl.ControlSize.small

    /// Sets the slim size on the vertical scroller of `scrollView` without laying it out; for a scroll view that
    /// calls this from its own `tile()`. Returns whether the size changed.
    @MainActor @discardableResult
    static func setControlSize(on scrollView: NSScrollView) -> Bool {
        guard let scroller = scrollView.verticalScroller, scroller.controlSize != controlSize else { return false }
        scroller.controlSize = controlSize
        return true
    }

    /// Applies the slim size to the vertical scroller of `scrollView`. Safe to call again.
    @MainActor static func apply(to scrollView: NSScrollView) {
        if setControlSize(on: scrollView) { scrollView.tile() }
    }
}

/// Calls `handler` when the system's "Show scroll bars" setting changes, which can rebuild a scroller. Keep the
/// observer alive as long as the scroll view it serves.
@MainActor
final class ScrollerStyleObserver: NSObject {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(changed), name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func changed(_ notification: Notification) { handler() }
}

extension View {
    /// Makes the scroll bar of the SwiftUI `ScrollView`, `List` or `TextEditor` this is attached to thinner.
    /// Attach it directly to that view, before any padding or frame that changes its size.
    func slimScrollers() -> some View { background(SlimScrollerProbe()) }
}

/// A zero-content view behind a scroll area. SwiftUI offers no handle on its `NSScrollView`, so the probe finds the
/// scroll view that covers the same rectangle in the window.
private struct SlimScrollerProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ view: ProbeView, context: Context) { view.scheduleApply() }
}

final class ProbeView: NSView {
    /// A search that finds nothing is repeated only this many times for the same size, so a scroll area that is
    /// not an `NSScrollView` at all does not make every layout pass walk the window.
    static let maxFailedSearches = 4

    private weak var target: NSScrollView?
    private var applyScheduled = false
    private var styleObserver: ScrollerStyleObserver?
    private var failedSearches = 0
    private var failedSize = NSSize.zero
    /// How many times this probe has searched the window; tests check that a hopeless search stops.
    private(set) var searchCount = 0

    /// Not a hit target and not part of the accessibility tree: the scroll area behind or in front of it is.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        target = nil
        failedSearches = 0
        scheduleApply()
        guard styleObserver == nil else { return }
        styleObserver = ScrollerStyleObserver { [weak self] in
            self?.failedSearches = 0
            self?.scheduleApply()
        }
    }

    override func layout() {
        super.layout()
        scheduleApply()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleApply()
    }

    /// Runs after the current layout pass, when the scroll view has its final frame.
    func scheduleApply() {
        guard !applyScheduled else { return }
        applyScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyScheduled = false
            self.apply()
        }
    }

    private func apply() {
        guard window != nil else { return }
        if target?.window !== window { target = nil }
        if target == nil {
            if bounds.size != failedSize { failedSize = bounds.size; failedSearches = 0 }
            guard failedSearches < Self.maxFailedSearches else { return }
            searchCount += 1
            target = findTarget()
            if target == nil { failedSearches += 1 }
        }
        if let target { SlimScroller.apply(to: target) }
    }

    /// The scroll view that covers this view's rectangle (the probe is the scroll area's background). A scroll view
    /// nested inside the area, or one around it, covers a different rectangle. The search starts next to the probe
    /// and widens one superview at a time, so it normally ends within the SwiftUI container around the scroll area.
    private func findTarget() -> NSScrollView? {
        let mine = convert(bounds, to: nil)
        guard mine.width > 0, mine.height > 0 else { return nil }
        var came: NSView = self
        var level = superview
        while let ancestor = level {
            if let found = bestMatch(in: ancestor, skipping: came, for: mine) { return found }
            came = ancestor
            level = ancestor.superview
        }
        return nil
    }

    private func bestMatch(in root: NSView, skipping skipped: NSView, for mine: NSRect) -> NSScrollView? {
        var best: (view: NSScrollView, overlap: CGFloat)?
        var stack = [root]
        while let view = stack.popLast() {
            if let scrollView = view as? NSScrollView {
                let overlap = Self.overlap(scrollView.convert(scrollView.bounds, to: nil), mine)
                if overlap > Self.minimumOverlap, overlap > (best?.overlap ?? 0) { best = (scrollView, overlap) }
            }
            // Rows of a list are not scroll areas.
            if view is NSTableView { continue }
            stack.append(contentsOf: view.subviews.filter { $0 !== skipped })
        }
        return best?.view
    }

    /// A scroll view that extends under the toolbar is taller than the probe, which stays in the safe area.
    static let minimumOverlap: CGFloat = 0.75

    /// Intersection over union of two rectangles: 1 for the same rectangle.
    static func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let shared = a.intersection(b)
        guard !shared.isNull, shared.width > 0, shared.height > 0 else { return 0 }
        let area = shared.width * shared.height
        return area / (a.width * a.height + b.width * b.height - area)
    }
}
