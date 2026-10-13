import Foundation
import PlopcutCore

/// Looks up user-facing text from the generated table. Korean for `ko*` system languages, English otherwise.
enum L10n {
    nonisolated(unsafe) static var languageOverride: String?

    static var isKorean: Bool {
        isKorean(language: languageOverride ?? Locale.preferredLanguages.first ?? "en")
    }

    /// Korean for any `ko*` language tag (checklist N-01); a pure function so tests need no shared state.
    static func isKorean(language: String) -> Bool { language.hasPrefix("ko") }

    static func t(_ key: String, _ values: [String: String] = [:]) -> String {
        guard let entry = StringTable.entries[key] else { return key }
        var text = isKorean ? entry.ko : entry.en
        for (name, value) in values { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
        return text
    }
}

/// Turns an error into the sentence the user sees (spec 6, checklist N-03): a known code gets its localized text,
/// anything else gets the generic message. The legacy app showed the raw message of an unknown code; `detail` here is
/// log text (paths, OS wording) and would mix languages into the UI, so it is deliberately never shown.
enum ErrorText {
    static func message(for error: Error) -> String {
        message(forCode: (error as? PlopcutError)?.code ?? "")
    }

    static func message(forCode code: String) -> String {
        localized(forCode: code) ?? L10n.t("defaultError")
    }

    private static func localized(forCode code: String) -> String? {
        switch code {
        case "blankTitle", "invalid_title": L10n.t("blankTitle")
        case "invalid_storage_folder", "storage_unwritable", "storage_unreadable": L10n.t("storageFailure")
        case "no_selected_text": L10n.t("noSelectedText")
        case "clipboard_unavailable": L10n.t("clipboardUnavailable")
        case "clipboard_changed": L10n.t("clipboardChanged")
        case "clipboard_empty": L10n.t("clipboardEmpty")
        case "clipboard_image_unavailable": L10n.t("invalidImage")
        case "clipboard_restore_failed": L10n.t("clipboardRestoreFailed")
        case "automation_failed", "automation_unavailable": L10n.t("automationFailed")
        case "invalid_selected_text_shortcut": L10n.t("shortcutFormatHint")
        case "shortcut_registration_failed": L10n.t("shortcutRegistrationFailed")
        case "shortcut_rollback_failed": L10n.t("shortcutRollbackFailed")
        case "permission_missing": L10n.t("permissionAccessibilityMissing")
        case "settings_invalid", "settings_unreadable", "settings_unwritable": L10n.t("settingsFailure")
        case "delete_failed": L10n.t("deleteFailed")
        case "drop_not_found", "invalid_drop_id": L10n.t("dropNotFound")
        case "export_failed": L10n.t("exportFailed")
        case "save_failed": L10n.t("saveFailed")
        case "empty_text": L10n.t("noCaptured")
        case "invalid_image", "empty_image": L10n.t("invalidImage")
        default: nil
        }
    }
}

/// The next step offered next to an error message (STA-78): a way forward, not only a reason.
enum ErrorRecovery: Equatable {
    case openAccessibilitySettings
    case openPlopcutSettings

    var titleKey: String {
        switch self {
        case .openAccessibilitySettings: "openSystemSettings"
        case .openPlopcutSettings: "openSettings"
        }
    }

    static func forCode(_ code: String) -> ErrorRecovery? {
        switch code {
        case "permission_missing": .openAccessibilitySettings
        case "invalid_storage_folder", "storage_unwritable", "storage_unreadable",
            "settings_invalid", "settings_unreadable", "settings_unwritable": .openPlopcutSettings
        default: nil
        }
    }

    static func forError(_ error: Error) -> ErrorRecovery? {
        forCode((error as? PlopcutError)?.code ?? "")
    }
}
