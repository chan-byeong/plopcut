import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// The window of one floating drop (spec 2.8): a non-activating utility panel that stays on top on its own Space, with
/// Open in Library and Collapse in the title bar. It turns translucent while the cursor is elsewhere and the user is
/// not typing in it. Nothing about it is saved.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate, FloatingPanel {
    private let id: String
    private let model: LibraryModel
    private let panel: FloatingPanelWindow
    private let background = FloatingPanelBackground()
    private let collapseButton = NSButton()
    private let didClose: () -> Void
    private var cursorInside = false
    /// The window height to return to while collapsed; `nil` when expanded.
    private var expandedHeight: CGFloat?
    private var accessibilityObserver: NSObjectProtocol?

    init(
        id: String, model: LibraryModel, cascade: Int, openInLibrary: @escaping () -> Void,
        didClose: @escaping () -> Void
    ) {
        self.id = id
        self.model = model
        self.didClose = didClose
        panel = FloatingPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: FloatingPanelLayout.defaultWidth, height: 200),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init()
        configureWindow()
        installContent()
        installTitleBarButtons(openInLibrary: openInLibrary)
        panel.setFrame(openingFrame(cascade: cascade), display: false)
        trackTitle()
        model.editor.attachPanel(id)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateOpacity() } }
    }

    // MARK: FloatingPanel

    func show() {
        cursorInside = panel.frame.contains(NSEvent.mouseLocation)
        updateOpacity(animated: false)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    func close() { panel.close() }

    var window: NSWindow { panel }

    // MARK: Window

    private func configureWindow() {
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.isExcludedFromWindowsMenu = true
        panel.becomesKeyOnlyIfNeeded = false
        // No `.canJoinAllSpaces` or `.fullScreenAuxiliary`: the panel stays on the Space it was floated on.
        // `.managed` shows it in Mission Control (a floating level is left out by default), so it can be dragged to
        // another Space there.
        panel.collectionBehavior = [.managed, .ignoresCycle]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setAccessibilitySubrole(.floatingWindow)
        panel.setAccessibilityRoleDescription(L10n.t("floatingPanel"))
        panel.delegate = self
        panel.toggleCollapse = { [weak self] in self?.toggleCollapse() }
        panel.onEscape = { [weak self] in self?.giveUpKeyboard() }
    }

    private func installContent() {
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.onHover = { [weak self] inside in
            self?.cursorInside = inside
            self?.updateOpacity()
        }
        panel.contentView = background
        let host = NSHostingView(rootView: FloatingPanelView(model: model, id: id))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        let guide = panel.contentLayoutGuide as? NSLayoutGuide
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: guide?.topAnchor ?? background.topAnchor),
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
    }

    private func installTitleBarButtons(openInLibrary: @escaping () -> Void) {
        let open = TitleBarButton(symbol: "arrow.up.forward.app", label: L10n.t("openInLibrary"), perform: openInLibrary)
        collapseButton.target = self
        collapseButton.action = #selector(collapseClicked)
        TitleBarButton.style(collapseButton)
        updateCollapseButton()
        let stack = NSStackView(views: [open, collapseButton])
        stack.spacing = Spacing.xs
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: Spacing.xs)
        // The title bar sizes an accessory by its frame, not its constraints.
        stack.frame.size = stack.fittingSize
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = stack
        accessory.layoutAttribute = .trailing
        panel.addTitlebarAccessoryViewController(accessory)
    }

    /// The window title follows the drop's title as the Library edits it.
    private func trackTitle() {
        withObservationTracking {
            panel.title = model.drops.first { $0.id == id }?.title ?? ""
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackTitle() }
        }
    }

    private var titleBarHeight: CGFloat { panel.frame.height - panel.contentLayoutRect.height }

    private func openingFrame(cascade: Int) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        let width = FloatingPanelLayout.defaultWidth
        let measure = NSHostingController(rootView: FloatingPanelView(model: model, id: id, measuring: true))
        let content = measure.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = FloatingPanelLayout.openingHeight(contentHeight: content.height, titleBar: titleBarHeight, in: visible)
        updateSizeLimits()
        return FloatingPanelLayout.openingFrame(size: NSSize(width: width, height: height), cascade: cascade, in: visible)
    }

    /// Width is at least 240 with no upper limit; the height locks to the title bar while collapsed.
    private func updateSizeLimits() {
        let minWidth = FloatingPanelLayout.minWidth
        let widest = CGFloat.greatestFiniteMagnitude
        if expandedHeight != nil {
            panel.minSize = NSSize(width: minWidth, height: titleBarHeight)
            panel.maxSize = NSSize(width: widest, height: titleBarHeight)
        } else {
            panel.minSize = NSSize(width: minWidth, height: titleBarHeight + FloatingPanelLayout.minContentHeight)
            panel.maxSize = NSSize(width: widest, height: widest)
        }
    }

    // MARK: Collapse

    @objc private func collapseClicked() { toggleCollapse() }

    /// Leaves only the title bar, or returns to the height before collapsing. The top edge stays put.
    func toggleCollapse() {
        var frame = panel.frame
        let top = frame.maxY
        if let height = expandedHeight {
            expandedHeight = nil
            frame.size.height = height
        } else {
            expandedHeight = frame.height
            frame.size.height = titleBarHeight
        }
        frame.origin.y = top - frame.height
        background.subviews.forEach { $0.isHidden = expandedHeight != nil }
        updateSizeLimits()
        panel.setFrame(frame, display: true, animate: false)
        updateCollapseButton()
    }

    var isCollapsed: Bool { expandedHeight != nil }

    private func updateCollapseButton() {
        let label = L10n.t(isCollapsed ? "expandPanel" : "collapsePanel")
        collapseButton.image = NSImage(
            systemSymbolName: isCollapsed ? "chevron.down" : "chevron.up", accessibilityDescription: label)
        collapseButton.toolTip = label
        collapseButton.setAccessibilityLabel(label)
    }

    /// Esc keeps the panel, saves the note at once, and hands the keyboard back: to the app the user was typing in,
    /// or to plopcut's own window when plopcut is active (spec 2.8).
    private func giveUpKeyboard() {
        guard panel.isKeyWindow else { return }
        let editor: DropEditor = model.editor
        Task { [id] in await editor.flushNote(of: id) }
        panel.makeFirstResponder(nil)
        if NSApp.isActive,
            let window = NSApp.windows.first(where: { $0 !== panel && $0.isVisible && $0.canBecomeMain })
        {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // A nonactivating panel takes the keyboard without making plopcut active, so the other app is still the
        // active one and activating it again does nothing. Taking the panel off screen for a moment drops its key
        // status, and the window server hands the keyboard back to that app's window.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Opacity

    private func updateOpacity(animated: Bool = true) {
        let workspace = NSWorkspace.shared
        let translucent = FloatingPanelLayout.isTranslucent(
            cursorInside: cursorInside, isKey: panel.isKeyWindow,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency)
        let alpha = translucent ? FloatingPanelLayout.idleOpacity : 1
        guard panel.alphaValue != alpha else { return }
        if animated, !workspace.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = FloatingPanelLayout.opacityTransition
                panel.animator().alphaValue = alpha
            }
        } else {
            panel.alphaValue = alpha
        }
    }

    func windowDidBecomeKey(_ notification: Notification) { updateOpacity() }

    func windowDidResignKey(_ notification: Notification) { updateOpacity() }

    func windowWillClose(_ notification: Notification) {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        // Whatever was typed is written now instead of waiting for the debounce.
        let editor: DropEditor = model.editor
        Task { [id] in await editor.detachPanel(id) }
        didClose()
    }
}

/// The panel's window. A non-activating panel gets no key equivalents from the menu, so it handles Cmd+W and the text
/// editing commands itself (like `SavePopupPanel`), and a double-click on the title bar collapses instead of zooming.
final class FloatingPanelWindow: NSPanel {
    var toggleCollapse: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey(event) { return }
        if event.type == .keyDown, Self.isPlainEscape(event), !isComposing {
            onEscape?()
            return
        }
        if event.type == .leftMouseDown || event.type == .leftMouseUp, event.clickCount == 2,
           isTitleBarBackground(event.locationInWindow) {
            if event.type == .leftMouseDown { toggleCollapse?() }
            return
        }
        super.sendEvent(event)
    }

    /// NSPanel closes on Esc; a floating panel stays and only gives up the keyboard.
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    /// The title bar's double-click is Collapse here; the system's zoom never applies to a floating panel.
    override func zoom(_ sender: Any?) {}

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        if Self.closesWindow(event) {
            performClose(nil)
            return true
        }
        if performKeyEquivalent(with: event) { return true }
        if let action = SavePopupPanel.editAction(for: event), let responder = firstResponder {
            return responder.tryToPerform(action, with: self)
        }
        return false
    }

    static func isPlainEscape(_ event: NSEvent) -> Bool {
        event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
    }

    /// An input method composition is open in the note; Escape then only ends it (checklist F-09).
    private var isComposing: Bool { (firstResponder as? NSTextView)?.hasMarkedText() == true }

    /// Cmd+W, by key position so a Korean layout works too.
    static func closesWindow(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command]
            && event.keyCode == UInt16(kVK_ANSI_W)
    }

    /// Above the content and not on one of the title bar's buttons (the title text counts as title bar).
    private func isTitleBarBackground(_ point: NSPoint) -> Bool {
        guard point.y > contentLayoutRect.maxY else { return false }
        return !(contentView?.superview?.hitTest(point) is NSButton)
    }
}

/// The translucent backdrop under the title bar and content; it reports the cursor entering and leaving the panel,
/// even while another app is active.
final class FloatingPanelBackground: NSVisualEffectView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }

    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// A small borderless symbol button for the panel's title bar, with a name and a tooltip.
final class TitleBarButton: NSButton {
    private var perform: (() -> Void)?

    convenience init(symbol: String, label: String, perform: @escaping () -> Void) {
        self.init(frame: .zero)
        self.perform = perform
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(clicked)
        Self.style(self)
    }

    /// A 22 pt square hit area, so the two buttons do not touch; the label color keeps them readable in dark mode
    /// and while the panel is translucent.
    static func style(_ button: NSButton) {
        button.isBordered = false
        button.bezelStyle = .accessoryBarAction
        button.imagePosition = .imageOnly
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
        ])
    }

    static let size: CGFloat = 22

    @objc private func clicked() { perform?() }
}
