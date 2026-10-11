import AppKit
import SwiftUI

/// The separate Save Popup window (spec 2.1): fixed size, always on top, centered, no title.
/// The hosting view adds the transparent title bar's height to `SavePopupView.contentSize`.
/// One window is reused; a new draft replaces the previous one (checklist P-14).
@MainActor
final class SavePopupWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var model: SavePopupModel?
    func show(_ model: SavePopupModel) {
        self.model = model
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: SavePopupView(model: model))
        if !panel.isVisible { panel.center() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// Brings the open popup back to the front without touching its draft.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Closes after a save or a cancel. `orderOut` does not call `windowShouldClose`.
    func close() {
        model = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: SavePopupView.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        return panel
    }

    /// The window's own close button discards the draft, like Cancel.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model?.isSaving == true { return false }
        model = nil
        return true
    }
}
