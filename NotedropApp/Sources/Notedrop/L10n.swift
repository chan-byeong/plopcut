import Foundation
import NotedropCore

/// Looks up user-facing text from the generated table. Korean for `ko*` system languages, English otherwise.
enum L10n {
    nonisolated(unsafe) static var languageOverride: String?

    static var isKorean: Bool {
        (languageOverride ?? Locale.preferredLanguages.first ?? "en").hasPrefix("ko")
    }

    static func t(_ key: String, _ values: [String: String] = [:]) -> String {
        guard let entry = StringTable.entries[key] else { return key }
        var text = isKorean ? entry.ko : entry.en
        for (name, value) in values { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
        return text
    }
}

/// Turns an error code from the storage layer into the sentence the user sees (spec 6).
enum ErrorText {
    static func message(for error: Error) -> String {
        message(forCode: (error as? NotedropError)?.code ?? "")
    }

    static func message(forCode code: String) -> String {
        switch code {
        case "blankTitle", "invalid_title": L10n.t("blankTitle")
        case "invalid_storage_folder", "storage_unwritable", "storage_unreadable": L10n.t("storageFailure")
        case "no_selected_text": L10n.t("noSelectedText")
        case "clipboard_unavailable": L10n.t("clipboardUnavailable")
        case "clipboard_changed": L10n.t("clipboardChanged")
        case "clipboard_empty": L10n.t("clipboardEmpty")
        case "clipboard_image_unavailable": L10n.t("invalidImage")
        case "clipboard_image_unsupported": L10n.t("clipboardImageUnsupported")
        case "permission_missing": L10n.t("permissionAccessibilityMissing")
        case "empty_text", "empty_image": L10n.t("noCaptured")
        case "invalid_image": L10n.t("invalidImage")
        default: L10n.t("defaultError")
        }
    }
}
