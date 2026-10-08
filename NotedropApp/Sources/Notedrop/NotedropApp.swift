import AppKit
import SwiftUI

@main
struct NotedropApp: App {
    @State private var model: LibraryModel
    @State private var capture: CaptureRuntime
    @State private var appearance: SettingsModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        let settings = LibraryModel.defaultSettings
        let model = LibraryModel(settings: settings)
        _model = State(initialValue: model)
        let appearance = SettingsModel(store: settings)
        _appearance = State(initialValue: appearance)
        _capture = State(initialValue: CaptureRuntime(model: model, settings: settings, appearance: appearance))
        // settings.json owns the column widths (spec L-15). AppKit's own split autosave would restore widths that a
        // narrow window squeezed, so drop it before the window is built.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSSplitView Subview Frames") {
            defaults.removeObject(forKey: key)
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow(model: model, settings: appearance)
                .modifier(OpenMainWindowBinding(runtime: capture))
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(appearance.colorScheme)
                .task {
                    CompositionMonitor.shared.install()
                    delegate.drain = { [model] in await model.editor.drain() }
                    delegate.showSaveFailure = { [model] in model.alertMessage = L10n.t("saveFailed") }
                    delegate.hasUnsavedEdits = { [model] in model.editor.hasUnsavedEdits }
                    capture.start()
                    model.presentPendingCaptureError()
                    await model.reload()
                }
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified)
    }
}

/// Holds quitting until edits typed in the last moments have been written (the autosave debounce is 600 ms).
/// If a write fails the first quit is cancelled and the user is told; asking to quit again quits anyway.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var drain: (() async -> Bool)?
    var hasUnsavedEdits: (() -> Bool)?
    var showSaveFailure: (() -> Void)?
    /// When the failure warning was shown. Asking to quit again soon after quits anyway; an old warning does not count.
    private var warnedAt: Date?
    private static let warningWindow: TimeInterval = 15

    /// The global shortcut must keep working with the main window closed (spec 2.1). D-07 is decided in stage 5.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let drain, hasUnsavedEdits?() == true else { return .terminateNow }
        Task {
            let saved = await drain()
            let recentlyWarned = warnedAt.map { Date().timeIntervalSince($0) < Self.warningWindow } ?? false
            if saved || recentlyWarned {
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
