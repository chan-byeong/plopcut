import Observation

/// Whether a drop is floating, and if so whether its panel is on screen (spec 2.8).
enum FloatingState: Equatable {
    case none, visible, hidden
}

/// One floating panel window. The registry decides when; the window only does what it is told.
@MainActor
protocol FloatingPanel: AnyObject {
    /// Puts the panel on screen in front without activating the app or taking the keyboard.
    func show()
    func hide()
    /// Closes the window for good. The window may still report the close through `panelDidClose`; that is a no-op.
    func close()
}

/// The drops floated on screen, in the order they were floated (spec 2.8). One panel per drop, no limit on how many.
/// Nothing here is saved: quitting closes every panel.
@MainActor @Observable
final class FloatingDrops {
    /// Floated drop ids, oldest first. The menu bar lists them in this order.
    private(set) var ids: [String] = []
    private var hidden: Set<String> = []
    @ObservationIgnored private var panels: [String: FloatingPanel] = [:]
    /// Builds the window for a drop; `cascade` is how many panels are already floating, so a new one does not land
    /// exactly on top of the last.
    @ObservationIgnored var makePanel: ((_ registry: FloatingDrops, _ id: String, _ cascade: Int) -> FloatingPanel)?

    init(makePanel: ((FloatingDrops, String, Int) -> FloatingPanel)? = nil) {
        self.makePanel = makePanel
    }

    /// Reads the observed `ids`, not the window table, so views showing the state redraw when it changes.
    func state(of id: String) -> FloatingState {
        guard ids.contains(id) else { return .none }
        return hidden.contains(id) ? .hidden : .visible
    }

    /// Whether any panel is hidden; then the menu offers Show All instead of Hide All.
    var hasHidden: Bool { !hidden.isEmpty }

    /// Floats the drop, or brings its existing panel back to the front.
    func float(_ id: String) {
        if panels[id] != nil { return show(id) }
        guard let panel = makePanel?(self, id, ids.count) else { return }
        panels[id] = panel
        ids.append(id)
        panel.show()
    }

    /// Shows a floating drop's panel, hidden or not, in front of the others.
    func show(_ id: String) {
        guard let panel = panels[id] else { return }
        hidden.remove(id)
        panel.show()
    }

    /// The drop view's Float on Screen button: floats the drop, closes its visible panel, or brings its hidden panel
    /// back (spec 2.8).
    func toggle(_ id: String) {
        switch state(of: id) {
        case .none: float(id)
        case .visible: close(id)
        case .hidden: show(id)
        }
    }

    func hideAll() {
        for id in ids where !hidden.contains(id) {
            hidden.insert(id)
            panels[id]?.hide()
        }
    }

    /// Shows the hidden panels, keeping the float order.
    func showAll() {
        for id in ids where hidden.contains(id) { show(id) }
    }

    func close(_ id: String) {
        guard let panel = forget(id) else { return }
        panel.close()
    }

    func closeAll() {
        for id in ids { close(id) }
    }

    /// Closes the panels whose drop is gone: moved to the Trash or missing after a reload (spec 2.8).
    func closeAll(except exists: (String) -> Bool) {
        for id in ids where !exists(id) { close(id) }
    }

    /// The panel's own close button or Cmd+W closed the window; only the bookkeeping is left.
    func panelDidClose(_ id: String) {
        _ = forget(id)
    }

    private func forget(_ id: String) -> FloatingPanel? {
        guard let panel = panels.removeValue(forKey: id) else { return nil }
        ids.removeAll { $0 == id }
        hidden.remove(id)
        return panel
    }
}
