import AppKit
import NotedropCore
import SwiftUI

/// Applies the saved pane widths once when the window opens. SwiftUI ignores `ideal` column widths on macOS, so this
/// finds the NavigationSplitView's NSSplitView and sets its dividers directly (spec L-15).
struct SplitViewRestorer: NSViewRepresentable {
    let widths: PaneWidths

    func makeNSView(context: Context) -> NSView { Probe(widths: widths) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        let widths: PaneWidths
        private var applied = false

        init(widths: PaneWidths) {
            self.widths = widths
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !applied, window != nil else { return }
            // Wait one turn so the split view has its first layout.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            guard !applied, let split = enclosingSplitView, split.arrangedSubviews.count >= 3 else { return }
            applied = true
            split.setPosition(widths.sidebar, ofDividerAt: 0)
            split.setPosition(widths.sidebar + widths.library, ofDividerAt: 1)
        }

        private var enclosingSplitView: NSSplitView? {
            var view = superview
            while let current = view {
                if let split = current as? NSSplitView, split.isVertical { return split }
                view = current.superview
            }
            return nil
        }
    }
}
