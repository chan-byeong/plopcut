import PlopcutCore

/// Decides which column-width changes come from the user dragging a divider (spec L-15).
/// Widths that shrink because the window got narrower are only recorded, never saved.
struct PaneWidthRecorder {
    private var last: (sidebar: Double, list: Double, window: Double)?

    /// Returns the widths to save, or nil when the change came from a window resize, a hidden column, rounding noise,
    /// or layout settling while no mouse button is down (launch, sidebar toggle).
    mutating func observe(sidebar: Double, list: Double, window: Double, mouseDown: Bool = true) -> PaneWidths? {
        // A collapsed sidebar or the settings view reports a zero-width column; keep the previous baseline.
        guard sidebar >= 1, list >= 1 else { return nil }
        defer { last = (sidebar, list, window) }
        guard mouseDown, let last, abs(last.window - window) < 1 else { return nil }
        let moved = abs(last.sidebar - sidebar) >= 1 || abs(last.list - list) >= 1
        return moved ? PaneWidths(sidebar: sidebar, library: list) : nil
    }
}
