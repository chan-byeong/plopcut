import AppKit

/// The menu bar item: a left or right click shows the menu without activating the app (checklist T-01, PLO-96).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let openMainWindow: () -> Void
    private let openSettings: () -> Void
    private let saveClipboard: () -> Void
    private var feedback: MenuBarFeedback?
    private var animation: Task<Void, Never>?

    init(openMainWindow: @escaping () -> Void, openSettings: @escaping () -> Void, saveClipboard: @escaping () -> Void) {
        self.openMainWindow = openMainWindow
        self.openSettings = openSettings
        self.saveClipboard = saveClipboard
        super.init()
        feedback = MenuBarFeedback(
            apply: { [weak self] in self?.show($0) },
            schedule: { delay, work in
                let task = Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    if !Task.isCancelled { work() }
                }
                return { task.cancel() }
            },
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion })
        statusItem.button?.imagePosition = .imageOnly
        // The status item opens its own menu on any click; the items are rebuilt each time it opens.
        menu.delegate = self
        statusItem.menu = menu
        show(.idle)
    }

    func showError(reason: String) { feedback?.showError(reason: reason) }
    func showSaved() { feedback?.showSaved() }

    /// The menu, with the failure on top while the exclamation mark is up (checklist T-05).
    static func menuItems(failure: String?) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let failure {
            items.append(NSMenuItem.sectionHeader(title: L10n.t("pendingFailed")))
            let reason = NSMenuItem(title: failure, action: nil, keyEquivalent: "")
            reason.isEnabled = false
            items.append(reason)
            items.append(.separator())
            items.append(item(.openSettings, "openSettings"))
        }
        items.append(item(.saveClipboard, "saveClipboard"))
        items.append(item(.openLibrary, "openLibrary"))
        return items
    }

    private static func item(_ action: MenuBarAction, _ titleKey: String) -> NSMenuItem {
        let item = NSMenuItem(title: L10n.t(titleKey), action: #selector(menuSelected(_:)), keyEquivalent: "")
        item.representedObject = action.rawValue
        return item
    }

    // MARK: Drawing

    /// Sets the final image at once, or plays the movement first. A new appearance stops the one still moving.
    private func show(_ appearance: MenuBarAppearance) {
        animation?.cancel()
        statusItem.button?.toolTip = appearance.tooltip
        guard let motion = appearance.motion else { return setImage(BrandMark.templateImage(appearance.accent), appearance) }
        let frames = Self.frames(motion)
        let step = (motion == .drop ? MenuBarFeedback.dropDuration : MenuBarFeedback.shakeDuration) / frames.count
        animation = Task { @MainActor [weak self] in
            for frame in frames {
                self?.setImage(BrandMark.templateImage(appearance.accent, accentLift: frame.lift, shift: frame.shift), appearance)
                try? await Task.sleep(for: step)
                if Task.isCancelled { return }
            }
            self?.setImage(BrandMark.templateImage(appearance.accent), appearance)
        }
    }

    private func setImage(_ image: NSImage, _ appearance: MenuBarAppearance) {
        image.accessibilityDescription = appearance.tooltip
        statusItem.button?.image = image
    }

    /// Offsets in mark units: the dot falls from above with an ease-out, the shake narrows as it settles.
    static func frames(_ motion: MenuBarAppearance.Motion) -> [(lift: CGFloat, shift: CGFloat)] {
        switch motion {
        case .drop:
            let count = 12
            return (0..<count).map { i in
                let t = CGFloat(i) / CGFloat(count)
                return (lift: 28 * (1 - t) * (1 - t), shift: 0)
            }
        case .shake:
            return [-6, 6, -5, 5, -3, 3, -1.5, 1.5, 0].map { (lift: 0, shift: $0) }
        }
    }

    // MARK: Menu

    /// Runs as the menu opens; the failure item needs `menuWillOpen()`'s answer, which also clears the exclamation mark.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in Self.menuItems(failure: feedback?.menuWillOpen()) {
            if item.action != nil { item.target = self }
            menu.addItem(item)
        }
    }

    @objc private func menuSelected(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let action = MenuBarAction(id: id) else { return }
        switch action {
        case .saveClipboard: saveClipboard()
        case .openLibrary: openMainWindow()
        case .openSettings: openSettings()
        }
    }
}
