import AppKit
import SwiftUI

@main
struct PlopcutApp: App {
    @State private var model: LibraryModel
    @State private var capture: CaptureRuntime
    @State private var appearance: SettingsModel
    @State private var folder: StorageFolderModel
    @State private var floating: FloatingDrops
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        AppLog.migrateLegacyFolders()
        AppLog.logStart()
        let settings = LibraryModel.defaultSettings
        let model = LibraryModel(settings: settings)
        _model = State(initialValue: model)
        let appearance = SettingsModel(store: settings)
        _appearance = State(initialValue: appearance)
        let floating = FloatingDrops()
        _floating = State(initialValue: floating)
        _folder = State(initialValue: StorageFolderModel(
            store: settings, picker: OpenPanelFolderPicker(),
            prepare: { [model] in await model.editor.drain() },
            onChanged: { [model, floating] in
                floating.closeAll()
                Task { await model.reload() }
            }))
        let capture = CaptureRuntime(model: model, settings: settings, appearance: appearance, floating: floating)
        _capture = State(initialValue: capture)
        Self.connect(floating, to: model, capture: capture)
        // settings.json owns the column widths (spec L-15). AppKit's own split autosave would restore widths that a
        // narrow window squeezed, so drop it before the window is built.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSSplitView Subview Frames") {
            defaults.removeObject(forKey: key)
        }
    }

    /// Floating panels show Library drops and close when their drop leaves the Library (spec 2.8).
    private static func connect(_ floating: FloatingDrops, to model: LibraryModel, capture: CaptureRuntime) {
        floating.makePanel = { [model, weak capture] registry, id, cascade in
            FloatingPanelController(
                id: id, model: model, cascade: cascade,
                openInLibrary: {
                    capture?.showMainWindow()
                    model.reveal(id)
                },
                didClose: { [weak registry] in registry?.panelDidClose(id) })
        }
        model.onDropsChanged = { [weak floating] drops in
            floating?.closeAll { id in drops.contains { $0.id == id } }
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow(model: model, settings: appearance)
                .environment(floating)
                .environment(capture.shortcutModel)
                .modifier(OpenMainWindowBinding(runtime: capture))
                .environment(folder)
                .modifier(FirstRunSheet(model: folder))
                .frame(minWidth: LayoutMetrics.windowMin.width, minHeight: LayoutMetrics.windowMin.height)
                .task {
                    CompositionMonitor.shared.install()
                    _ = SourceAppIcons.shared  // starts building the app index before the list needs it
                    delegate.prepareToQuit = { [model] in
                        await model.editor.prepareToQuit(ask: BodyDraftQuitAlert.ask)
                    }
                    delegate.showSaveFailure = { [model] in model.alertMessage = L10n.t("saveFailed") }
                    delegate.needsWorkBeforeQuit = { [model] in model.editor.needsWorkBeforeQuit }
                    capture.start()
                    model.presentPendingCaptureError()
                    await model.reload()
                }
        }
        .defaultSize(LayoutMetrics.windowDefault)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .pasteboard) {
                PinCommand(model: model)
                EditBodyCommand(model: model)
                TrashCommand()
            }
            CommandGroup(after: .toolbar) { RefreshCommand(model: model) }
        }
    }
}

/// Holds quitting until edits typed in the last moments have been written (the autosave debounce is 600 ms).
/// If a write fails the first quit is cancelled and the user is told; asking to quit again quits anyway.
/// A changed content draft is never saved on its own: the user picks Save, Don't Save or Cancel first (E-16).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var prepareToQuit: (() async -> QuitPreparation)?
    var needsWorkBeforeQuit: (() -> Bool)?
    var showSaveFailure: (() -> Void)?
    /// When the failure warning was shown. Asking to quit again soon after quits anyway; an old warning does not count.
    private var warnedAt: Date?
    private static let warningWindow: TimeInterval = 15

    /// The global shortcut must keep working with the main window closed (spec 2.1). D-07 (decided in STA-52): the app stays in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let prepareToQuit, needsWorkBeforeQuit?() == true else { return .terminateNow }
        Task {
            let result = await prepareToQuit()
            if result == .cancelled {
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            let recentlyWarned = warnedAt.map { Date().timeIntervalSince($0) < Self.warningWindow } ?? false
            if result == .ready || recentlyWarned {
                sender.reply(toApplicationShouldTerminate: true)
            } else {
                warnedAt = Date()
                showSaveFailure?()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
