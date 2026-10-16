import AppKit

/// The menu bar item: left click opens the main window, right click shows the menu (checklist T-01).
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let openMainWindow: () -> Void
    private let saveClipboard: () -> Void
    private var feedback: MenuBarFeedback?

    init(openMainWindow: @escaping () -> Void, saveClipboard: @escaping () -> Void) {
        self.openMainWindow = openMainWindow
        self.saveClipboard = saveClipboard
        super.init()
        feedback = MenuBarFeedback(
            apply: { [weak self] title, tooltip in
                self?.statusItem.button?.title = title ?? ""
                self?.statusItem.button?.toolTip = tooltip
            },
            schedule: { delay, work in
                let task = Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    if !Task.isCancelled { work() }
                }
                return { task.cancel() }
            })
        if let button = statusItem.button {
            let image = BrandMark.templateImage(.dot)
            image.accessibilityDescription = MenuBarFeedback.idleTooltip
            button.image = image
            button.imagePosition = .imageLeading
            button.toolTip = MenuBarFeedback.idleTooltip
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        for (action, title) in [(MenuBarAction.saveClipboard, "saveClipboard"), (.openLibrary, "openLibrary")] {
            let item = NSMenuItem(title: L10n.t(title), action: #selector(menuSelected(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue
            item.target = self
            menu.addItem(item)
        }
    }

    func showError() { feedback?.showError() }
    func showSaved() { feedback?.showSaved() }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return openMainWindow() }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)  // shows the menu for this click only
            statusItem.menu = nil
        } else {
            openMainWindow()
        }
    }

    @objc private func menuSelected(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let action = MenuBarAction(id: id) else { return }
        switch action {
        case .saveClipboard: saveClipboard()
        case .openLibrary: openMainWindow()
        }
    }
}
