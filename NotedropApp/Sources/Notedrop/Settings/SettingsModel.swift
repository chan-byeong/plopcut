import AppKit
import Foundation
import NotedropCore
import Observation
import SwiftUI

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

    init(store: SettingsStore?, appVersion: String = SettingsModel.bundleVersion(from: Bundle.main.infoDictionary ?? [:]),
         devOverride: ColorScheme? = SettingsModel.environmentOverride) {
        self.store = store
        self.appVersion = appVersion
        self.devOverride = devOverride
        var stored: AppSettings?
        var loadError: String?
        do { stored = try store?.read() } catch { loadError = ErrorText.message(for: error) }
        theme = stored?.theme ?? .system
        captureMode = stored?.captureConfirmationMode ?? .modal
        errorMessage = loadError
        applyAppearance()
    }

    /// Setting the app appearance explicitly is what lets `system` release an earlier light/dark override;
    /// `preferredColorScheme(nil)` alone does not reliably do that on macOS.
    func applyAppearance() {
        NSApp?.appearance = switch colorScheme {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    /// The scheme to force on every Notedrop window; `nil` leaves it to the system.
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

    /// `NOTEDROP_APPEARANCE=light|dark` forces a scheme for screenshots while the theme setting is `system`.
    nonisolated static var environmentOverride: ColorScheme? {
        switch ProcessInfo.processInfo.environment["NOTEDROP_APPEARANCE"] {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
