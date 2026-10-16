import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The separate Save Popup window (spec 2.1): sized to its content, always on top, centered, no title.
/// The hosting view adds the transparent title bar's height to `SavePopupView.contentSize`. The window never gets
/// taller than the screen's visible area and stays inside it when it grows (STA-67).
/// One window is reused; a new draft replaces the previous one (checklist P-14).
/// A non-activating panel: it takes the keyboard without activating plopcut, so the main window stays where it is and
/// the app the user was working in keeps focus after a save or a cancel (PLO-96).
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
        panel.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// The popup window, once it has been shown.
    var window: NSWindow? { panel }

    /// Brings the open popup back to the front without touching its draft.
    func bringToFront() {
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Closes after a save or a cancel. `orderOut` does not call `windowShouldClose`.
    func close() {
        model = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = SavePopupPanel(
            contentRect: NSRect(origin: .zero, size: SavePopupView.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
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

/// The popup's panel. It does not activate plopcut, and AppKit only offers key equivalents to the active app, so the
/// panel routes the ones that reach it unhandled: the buttons' Cmd+Enter and Escape, then the text editing commands the
/// Edit menu would send (Cmd+V and the like). When plopcut is active, AppKit has already offered them to the window and
/// the menu, so only a key nobody handled gets here and asking again changes nothing.
final class SavePopupPanel: NSPanel {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, Self.routesAsKeyEquivalent(event), handleKeyEquivalent(event) {
            return
        }
        super.sendEvent(event)
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        if performKeyEquivalent(with: event) { return true }
        if let action = Self.editAction(for: event), let responder = firstResponder {
            return responder.tryToPerform(action, with: self)
        }
        return false
    }

    /// The Edit menu's text commands by their usual shortcuts.
    static func editAction(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = letter(of: event)
        switch (flags, key) {
        case ([.command], "x"): return #selector(NSText.cut(_:))
        case ([.command], "c"): return #selector(NSText.copy(_:))
        case ([.command], "v"): return #selector(NSText.paste(_:))
        case ([.command], "a"): return #selector(NSText.selectAll(_:))
        case ([.command], "z"): return Selector(("undo:"))
        case ([.command, .shift], "z"): return Selector(("redo:"))
        default: return nil
        }
    }

    /// The typed letter, or for a layout without Latin letters (Korean), the letter at that key's ANSI position.
    private static func letter(of event: NSEvent) -> String? {
        if let typed = event.charactersIgnoringModifiers?.lowercased(), typed.count == 1, typed.first?.isASCII == true {
            return typed
        }
        let letters = [kVK_ANSI_X: "x", kVK_ANSI_C: "c", kVK_ANSI_V: "v", kVK_ANSI_A: "a", kVK_ANSI_Z: "z"]
        return letters[Int(event.keyCode)]
    }

    /// Command shortcuts and Escape; plain typing (Return in the tag field included) stays with the text fields.
    static func routesAsKeyEquivalent(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) || event.keyCode == UInt16(kVK_Escape)
    }
}
