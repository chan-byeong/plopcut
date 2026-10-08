import AppKit

/// The menu bar item: left click opens the main window, right click shows the menu (checklist T-01).
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let openMainWindow: () -> Void
    private var feedback: MenuBarFeedback?

    init(openMainWindow: @escaping () -> Void) {
        self.openMainWindow = openMainWindow
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
            let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: MenuBarFeedback.idleTooltip)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.toolTip = MenuBarFeedback.idleTooltip
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let open = NSMenuItem(title: L10n.t("openLibrary"), action: #selector(menuSelected(_:)), keyEquivalent: "")
        open.representedObject = MenuBarAction.openLibrary.rawValue
        open.target = self
        menu.addItem(open)
    }

    func showError() { feedback?.showError() }

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
        case .openLibrary: openMainWindow()
        }
    }
}
