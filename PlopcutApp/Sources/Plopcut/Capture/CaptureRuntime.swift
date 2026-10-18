import AppKit
import PlopcutCore
import SwiftUI

/// Wires the capture pieces together at app launch: global shortcut -> capture -> Save Popup -> storage -> Library.
@MainActor
final class CaptureRuntime {
    private let model: LibraryModel
    private let settings: SettingsStore
    private let popup: SavePopupWindowController
    private var coordinator: CaptureCoordinator?
    private var clipboardCoordinator: CaptureCoordinator?
    private lazy var shortcuts = ShortcutController(
        registrar: GlobalHotKeyRegistrar(action: { [weak self] in self?.shortcutPressed() }))
    private var started = false
    private var didPromptForAccessibility = false
    private var menuBar: MenuBarController?

    /// Set by the main window when it appears; opens the window again after it was closed.
    var openMainWindow: (() -> Void)?

    init(model: LibraryModel, settings: SettingsStore, appearance: SettingsModel) {
        self.model = model
        self.settings = settings
        self.popup = SavePopupWindowController()
    }

    func start() {
        guard !started else { return }
        started = true
        menuBar = MenuBarController(
            openMainWindow: { [weak self] in self?.showMainWindow() },
            openSettings: { [weak self] in
                self?.model.collection = .settings
                self?.showMainWindow()
            },
            saveClipboard: { [weak self] in self?.saveClipboard() })

        let gate = CaptureGate()
        coordinator = CaptureCoordinator(
            capture: { try await Self.captureSelectedText() },
            present: { [weak self] draft in await self?.router.route(draft) },
            failed: { [weak self] in self?.report($0) }, gate: gate)

        clipboardCoordinator = CaptureCoordinator(
            capture: { try await Self.captureClipboard() },
            present: { [weak self] draft in await self?.router.route(draft) },
            failed: { [weak self] in self?.reportQuietly($0) }, gate: gate)

        do {
            let text = (try? settings.read().selectedTextShortcut) ?? SettingsStore.defaultShortcut
            try shortcuts.start(text)
        } catch let error as PlopcutError {
            reportQuietly(error)  // C-09: kept for the main window and shown as `Error` in the menu bar
        } catch {
            reportQuietly(PlopcutError("shortcut_registration_failed", detail: error.localizedDescription))
        }
    }

    // MARK: Shortcut

    /// The settings field for the shortcut; its change goes register -> release -> save (checklist C-08).
    var shortcutModel: ShortcutModel {
        if let createdShortcutModel { return createdShortcutModel }
        let model = ShortcutModel(
            initial: (try? settings.read().selectedTextShortcut) ?? SettingsStore.defaultShortcut,
            apply: { [weak self] in try self?.changeShortcut($0) })
        createdShortcutModel = model
        return model
    }

    /// Only the Settings screen creates the model; a hot key press must not create it (or read settings) on the way.
    private var createdShortcutModel: ShortcutModel?

    private func changeShortcut(_ text: String) throws {
        try shortcuts.change(to: text) { [settings] in _ = try settings.update(SettingsUpdate(selectedTextShortcut: $0)) }
    }

    /// Runs on the main actor: `GlobalHotKey` hops to the main queue before calling its `@MainActor` action.
    private func shortcutPressed() {
        // While Settings records a new shortcut, pressing the live one keeps it instead of capturing (STA-69).
        if createdShortcutModel?.currentShortcutPressed() == true { return }
        guard let coordinator else { return }
        // The popup holds the keyboard while it is open, so a capture would read the popup itself. Show the
        // popup instead (a deliberate difference from checklist P-14, which expects the draft to be replaced).
        if popup.isVisible { popup.bringToFront(); return }
        Task { await coordinator.trigger() }
    }

    // MARK: Capture

    private static func captureSelectedText() async throws -> CaptureDraft {
        try await SelectedTextCapture(
            reader: AXSelectedTextReader(), clipboard: SystemClipboard(), sender: CGEventCopySender(),
            collector: FrontmostSourceCollector(), frontmost: FrontmostSourceCollector.currentTarget,
            sleep: { try? await Task.sleep(for: $0) }
        ).capture()
    }

    private nonisolated static func captureClipboard() async throws -> CaptureDraft {
        try await ClipboardCapture(
            clipboard: SystemClipboard(), collector: FrontmostSourceCollector(),
            frontmost: FrontmostSourceCollector.currentTarget,
            isplopcut: { $0?.processID == ProcessInfo.processInfo.processIdentifier }
        ).capture()
    }

    /// Menu bar `Save Clipboard` (spec 3.2).
    private func saveClipboard() {
        guard let clipboardCoordinator else { return }
        if popup.isVisible { popup.bringToFront(); return }
        Task { await clipboardCoordinator.trigger() }
    }

    /// A failed capture or save only shows the failure in the menu bar and keeps the message for the next time the
    /// main window opens; it never raises the window itself (checklist K-06, P-13, PLO-96).
    private func reportQuietly(_ error: PlopcutError) {
        AppLog.shared.log(error: error)
        menuBar?.showError(reason: ErrorText.message(for: error))
        model.pendingCapture.store(error)
    }

    /// A failed selected-text capture stays quiet like the others, except a missing Accessibility permission: the
    /// shortcut cannot work at all without it, so the main window opens with the reason and `Open System Settings`.
    private func report(_ error: PlopcutError) {
        reportQuietly(error)
        guard error.code == "permission_missing" else { return }
        if !didPromptForAccessibility {
            didPromptForAccessibility = true  // once per launch; the message in the main window repeats the guidance
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        showMainWindow()
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier == MainWindowTag.identifier }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        model.presentPendingCaptureError()  // T-04: a kept error is shown when the window opens, once
    }

    // MARK: Routing and Save Popup

    /// Reads the confirmation mode from settings on every draft; an unreadable file falls back to the popup.
    private lazy var router = CaptureRouter(
        mode: { [settings] in (try? settings.read().captureConfirmationMode) ?? .modal },
        save: { [storageRoot = LibraryModel.defaultStorageRoot] request in
            try await Self.save(request, storageRoot: storageRoot)
        },
        showPopup: { [weak self] in self?.present($0) },
        saved: { [weak self] in self?.savedInstantly($0) },
        failed: { [weak self] in self?.reportQuietly($0) })

    /// `instant` save done: no popup to close and no tags to remember, so only the feedback and the Library change.
    private func savedInstantly(_ drop: Drop) {
        menuBar?.showSaved()
        Task { await model.reload(selecting: drop.id) }
    }

    private func present(_ draft: CaptureDraft) {
        let recent = (try? settings.read().recentTags) ?? []
        let popupModel = SavePopupModel(
            draft: draft, recentTags: recent,
            save: { [storageRoot = LibraryModel.defaultStorageRoot] request in
                try await Self.save(request, storageRoot: storageRoot)
            },
            onSaved: { [weak self] drop in self?.saved(drop) },
            onCancel: { [weak self] in self?.popup.close() })
        popup.show(popupModel)
    }

    private static func save(_ request: SaveRequest, storageRoot: @escaping @Sendable () throws -> URL) async throws -> Drop {
        try await Task.detached {
            let root = try storageRoot()
            try StorageFolderCheck.ensureUsable(root)
            let store = DropStore(root: root)
            if let png = request.imagePNG {
                return try store.saveImage(
                    png, title: request.title, source: request.source, tags: request.tags, note: request.note,
                    pinned: request.pinned)
            }
            return try store.saveText(
                request.text, title: request.title, source: request.source, tags: request.tags, note: request.note,
                pinned: request.pinned)
        }.value
    }

    private func saved(_ drop: Drop) {
        popup.close()
        menuBar?.showSaved()  // T-03: a popup save shows the same success feedback as an instant save (PLO-98)
        if let current = try? settings.read() {
            let merged = Tags.mergeRecent(new: drop.tags, existing: current.recentTags)
            // Recent tags are a convenience; a failed write must not undo a successful save.
            _ = try? settings.update(SettingsUpdate(recentTags: merged))
        }
        Task { await model.reload(selecting: drop.id) }
    }
}

/// Gives the runtime a way to reopen the main window after the user closed it.
struct OpenMainWindowBinding: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let runtime: CaptureRuntime

    func body(content: Content) -> some View {
        content
            .background(MainWindowTag())
            .onAppear { runtime.openMainWindow = { openWindow(id: "main") } }
    }
}

/// Marks the hosting window so it can be found by identifier, not by "first normal window".
struct MainWindowTag: NSViewRepresentable {
    static let identifier = NSUserInterfaceItemIdentifier("plopcut.main")

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.identifier = Self.identifier }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.window?.identifier != Self.identifier { view.window?.identifier = Self.identifier }
    }
}
