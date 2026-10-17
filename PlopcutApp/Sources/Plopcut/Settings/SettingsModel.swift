import AppKit
import Foundation
import PlopcutCore
import Observation
import SwiftUI

/// What the theme changes on the running application; `NSApplication` in the app, a fake in tests.
@MainActor
protocol ThemedApplication: AnyObject {
    var appearance: NSAppearance? { get set }
    var windows: [NSWindow] { get }
}

extension NSApplication: ThemedApplication {}

/// The values the settings screen edits. Each change is written to settings.json on its own (spec C-03: only the
/// sent field changes) and rolled back on screen when the write fails.
@MainActor
@Observable
final class SettingsModel {
    private(set) var theme: Theme
    private(set) var captureMode: CaptureConfirmationMode
    let appVersion: String
    private(set) var errorMessage: String?

    private let store: SettingsStore?
    private let devOverride: ColorScheme?
    private let application: () -> ThemedApplication?
    @ObservationIgnored private var launchObserver: NSObjectProtocol?

    /// `application` and `launch` are seams for tests; the app passes neither.
    init(store: SettingsStore?, appVersion: String = SettingsModel.bundleVersion(from: Bundle.main.infoDictionary ?? [:]),
         devOverride: ColorScheme? = SettingsModel.environmentOverride,
         application: @escaping () -> ThemedApplication? = { NSApp }, launch: NotificationCenter = .default) {
        self.store = store
        self.appVersion = appVersion
        self.devOverride = devOverride
        self.application = application
        var stored: AppSettings?
        var loadError: String?
        do { stored = try store?.read() } catch { loadError = ErrorText.message(for: error) }
        theme = stored?.theme ?? .system
        captureMode = stored?.captureConfirmationMode ?? .modal
        errorMessage = loadError
        if application() != nil {
            applyAppearance()
        } else {
            applyWhenLaunching(launch)
        }
    }

    /// The model is made in `App.init`, before AppKit creates `NSApp` (PLO-95). The stored theme is applied as the app
    /// starts launching, which is before SwiftUI builds the first window, so the window never shows the wrong scheme.
    private func applyWhenLaunching(_ launch: NotificationCenter) {
        launchObserver = launch.addObserver(
            forName: NSApplication.willFinishLaunchingNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let observer = self.launchObserver { launch.removeObserver(observer) }
                self.launchObserver = nil
                self.applyAppearance()
            }
        }
    }

    /// The single place the theme reaches the windows. `preferredColorScheme` is not used: it pins a per-window
    /// appearance that `nil` does not release, which left windows light after switching back to `system`.
    func applyAppearance() {
        guard let app = application() else { return }
        app.appearance = switch colorScheme {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        default: nil
        }
        for window in app.windows { window.appearance = nil }
    }

    /// The scheme to force on every plopcut window; `nil` leaves it to the system.
    var colorScheme: ColorScheme? {
        switch theme {
        case .light: .light
        case .dark: .dark
        case .system: devOverride
        }
    }

    func setTheme(_ value: Theme) {
        guard value != theme else { return }
        let previous = theme
        theme = value
        if !persist(SettingsUpdate(theme: value)) { theme = previous }
        applyAppearance()
    }

    func setCaptureMode(_ value: CaptureConfirmationMode) {
        guard value != captureMode else { return }
        let previous = captureMode
        captureMode = value
        if !persist(SettingsUpdate(captureConfirmationMode: value)) { captureMode = previous }
    }

    private func persist(_ change: SettingsUpdate) -> Bool {
        guard let store else { return true }
        do {
            _ = try store.update(change)
            errorMessage = nil
            return true
        } catch {
            errorMessage = ErrorText.message(for: error)
            return false
        }
    }

    nonisolated static func bundleVersion(from info: [String: Any]) -> String {
        (info["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    /// `PLOPCUT_APPEARANCE=light|dark` forces a scheme for screenshots while the theme setting is `system`.
    nonisolated static var environmentOverride: ColorScheme? {
        switch ProcessInfo.processInfo.environment["PLOPCUT_APPEARANCE"] {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
