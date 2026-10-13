import AppKit
import SwiftUI

/// The separate Save Popup window (spec 2.1): sized to its content, always on top, centered, no title.
/// The hosting view adds the transparent title bar's height to `SavePopupView.contentSize`. The window never gets
/// taller than the screen's visible area and stays inside it when it grows (STA-67).
/// One window is reused; a new draft replaces the previous one (checklist P-14).
@MainActor
final class SavePopupWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var model: SavePopupModel?
    private let visibleFrame: @MainActor (NSWindow) -> NSRect?

    /// `visibleFrame` is the area the popup must fit in; tests pass a small screen.
    init(visibleFrame: @escaping @MainActor (NSWindow) -> NSRect? = { ($0.screen ?? NSScreen.main)?.visibleFrame }) {
        self.visibleFrame = visibleFrame
    }

    func show(_ model: SavePopupModel) {
        self.model = model
        let panel = panel ?? makePanel()
        self.panel = panel
        // The title bar is hidden, but VoiceOver announces the window by its title.
        panel.title = L10n.t(model.selectedType == .image ? "saveImage" : "saveText")
        let area = visibleFrame(panel)
        let titleBar = panel.frame.height - panel.contentLayoutRect.height
        let host = NSHostingView(rootView: SavePopupView(model: model, maxHeight: area.map { $0.height - titleBar } ?? .infinity))
        panel.contentView = host
        // Size for this draft now: a reused panel still has the previous draft's height until the next layout.
        host.layoutSubtreeIfNeeded()
        panel.setContentSize(host.fittingSize)
        if !panel.isVisible {
            if let area {
                panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
            } else {
                panel.center()
            }
        }
        keepInside(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// The popup window, once it has been shown.
    var window: NSWindow? { panel }

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

    /// The window grows downward as tags are added; move it up when its bottom leaves the visible area.
    func windowDidResize(_ notification: Notification) {
        if let panel { keepInside(panel) }
    }

    private func keepInside(_ window: NSWindow) {
        guard let area = visibleFrame(window) else { return }
        var origin = window.frame.origin
        if window.frame.minY < area.minY { origin.y = area.minY }
        if origin.y + window.frame.height > area.maxY { origin.y = max(area.minY, area.maxY - window.frame.height) }
        if origin != window.frame.origin { window.setFrameOrigin(origin) }
    }

    /// The window's own close button discards the draft, like Cancel.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model?.isSaving == true { return false }
        model = nil
        return true
    }
}
