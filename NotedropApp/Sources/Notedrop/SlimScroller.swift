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

    /// Applies the slim size to the vertical scroller of `scrollView`. Safe to call again.
    @MainActor static func apply(to scrollView: NSScrollView) {
        guard let scroller = scrollView.verticalScroller, scroller.controlSize != controlSize else { return }
        scroller.controlSize = controlSize
        scrollView.tile()
    }
}

extension View {
    /// Makes the scroll bar of the SwiftUI `ScrollView`, `List` or `TextEditor` this is attached to thinner.
    /// Attach it directly to that view, before any padding or frame that changes its size.
    func slimScrollers() -> some View { background(SlimScrollerProbe()) }
}

/// A zero-content view behind a scroll area. SwiftUI offers no handle on its `NSScrollView`, so the probe finds the
/// scroll view that has the same frame as the probe in the window.
private struct SlimScrollerProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ view: ProbeView, context: Context) { view.scheduleApply() }
}

private final class ProbeView: NSView {
    private weak var target: NSScrollView?
    private var applyScheduled = false
    private var observesStyle = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        target = nil
        scheduleApply()
        guard !observesStyle else { return }
        observesStyle = true
        // A change of the system's scroll bar setting can rebuild the scroller.
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollerStyleChanged), name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrollerStyleChanged(_ notification: Notification) { scheduleApply() }

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
        if target == nil || target?.window !== window { target = findTarget() }
        if let target { SlimScroller.apply(to: target) }
    }

    /// The scroll view whose frame matches this view's (the probe is the scroll area's background). A scroll view
    /// nested inside the area, or one around it, covers a different rectangle.
    private func findTarget() -> NSScrollView? {
        guard let root = window?.contentView?.superview ?? window?.contentView else { return nil }
        let mine = convert(bounds, to: nil)
        guard mine.width > 0, mine.height > 0 else { return nil }
        var best: (view: NSScrollView, overlap: CGFloat)?
        var stack = [root]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scrollView = view as? NSScrollView else { continue }
            let frame = scrollView.convert(scrollView.bounds, to: nil)
            let shared = frame.intersection(mine)
            guard !shared.isNull else { continue }
            // Intersection over union: 1 for the same rectangle.
            let overlap = (shared.width * shared.height) / (frame.width * frame.height + mine.width * mine.height - shared.width * shared.height)
            if overlap > 0.9, overlap > (best?.overlap ?? 0) { best = (scrollView, overlap) }
        }
        return best?.view
    }
}
