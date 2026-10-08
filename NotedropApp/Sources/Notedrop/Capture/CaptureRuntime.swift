import AppKit
import NotedropCore
import SwiftUI

/// Wires the capture pieces together at app launch: global shortcut -> capture -> Save Popup -> storage -> Library.
@MainActor
final class CaptureRuntime {
    private let model: LibraryModel
    private let settings: SettingsStore
    private let popup: SavePopupWindowController
    private var hotKey: GlobalHotKey?
    private var coordinator: CaptureCoordinator?
    private var started = false
    private var didPromptForAccessibility = false

    /// Set by the main window when it appears; opens the window again after it was closed.
    var openMainWindow: (() -> Void)?

    init(model: LibraryModel, settings: SettingsStore, appearance: SettingsModel) {
        self.model = model
        self.settings = settings
        self.popup = SavePopupWindowController(settings: appearance)
    }

    func start() {
        guard !started else { return }
        started = true

        coordinator = CaptureCoordinator(
            capture: { try await Self.captureSelectedText() },
            present: { [weak self] in self?.present($0) },
            failed: { [weak self] in self?.report($0) })

        let hotKey = GlobalHotKey { [weak self] in
            guard let self, let coordinator else { return }
            // Notedrop is frontmost while its popup is open, so a capture would read Notedrop itself. Show the
            // popup instead (a deliberate difference from checklist P-14, which expects the draft to be replaced).
            if popup.isVisible { popup.bringToFront(); return }
            Task { await coordinator.trigger() }
        }
        self.hotKey = hotKey
        do {
            let text = (try? settings.read().selectedTextShortcut) ?? SettingsStore.defaultShortcut
            try hotKey.register(try Shortcut.parse(text))
        } catch let error as NotedropError {
            model.pendingCapture.store(error)
        } catch {
            model.pendingCapture.store(NotedropError("shortcut_registration_failed", detail: error.localizedDescription))
        }
    }

    // MARK: Capture

    private static func captureSelectedText() async throws -> CaptureDraft {
        try await SelectedTextCapture(
            reader: AXSelectedTextReader(), clipboard: SystemClipboard(), sender: CGEventCopySender(),
            collector: FrontmostSourceCollector(), sleep: { try? await Task.sleep(for: $0) }
        ).capture()
    }

    private func report(_ error: NotedropError) {
        if error.code == "permission_missing", !didPromptForAccessibility {
            didPromptForAccessibility = true  // once per launch; the message in the main window repeats the guidance
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        model.pendingCapture.store(error)
        showMainWindow()
        model.presentPendingCaptureError()
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    // MARK: Save Popup

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
            return try DropStore(root: root).saveText(
                request.text, title: request.title, source: request.source, tags: request.tags, note: request.note)
        }.value
    }

    private func saved(_ drop: Drop) {
        popup.close()
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
        content.onAppear { runtime.openMainWindow = { openWindow(id: "main") } }
    }
}
