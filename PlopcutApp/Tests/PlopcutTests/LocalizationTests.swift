import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

/// These tests never touch `L10n.languageOverride`, which other suites set while running in parallel.
@Suite struct LocalizationTests {
    // N-01
    @Test func koreanSystemLanguagesGetKoreanAndEverythingElseEnglish() {
        for (language, korean) in [("ko", true), ("ko-KR", true), ("en", false), ("en-US", false), ("ja", false), ("", false)] {
            #expect(L10n.isKorean(language: language) == korean, "\(language)")
        }
    }

    // N-02: the table holds both languages for every key, so a one-sided phrase cannot exist; both must be filled
    // and use the same placeholders.
    @Test func everyPhraseHasBothLanguagesWithTheSamePlaceholders() {
        func placeholders(_ text: String) -> Set<String> {
            Set(text.matches(of: /\{(\w+)\}/).map { String($0.1) })
        }
        for (key, entry) in StringTable.entries {
            #expect(!entry.en.isEmpty && !entry.ko.isEmpty, "\(key)")
            #expect(placeholders(entry.en) == placeholders(entry.ko), "\(key)")
        }
    }

    // N-03
    private static let knownCodes: [String: String] = [
        "no_selected_text": "noSelectedText", "clipboard_empty": "clipboardEmpty",
        "clipboard_unavailable": "clipboardUnavailable", "clipboard_changed": "clipboardChanged",
        "clipboard_image_unavailable": "invalidImage", "clipboard_restore_failed": "clipboardRestoreFailed",
        "automation_failed": "automationFailed", "automation_unavailable": "automationFailed",
        "invalid_image": "invalidImage", "empty_image": "invalidImage", "empty_text": "noCaptured",
        "invalid_storage_folder": "storageFailure", "storage_unwritable": "storageFailure",
        "storage_unreadable": "storageFailure", "permission_missing": "permissionAccessibilityMissing",
        "settings_invalid": "settingsFailure", "settings_unreadable": "settingsFailure",
        "settings_unwritable": "settingsFailure", "delete_failed": "deleteFailed", "drop_not_found": "dropNotFound",
        "invalid_drop_id": "dropNotFound", "export_failed": "exportFailed", "save_failed": "saveFailed",
    ]

    /// Either language is accepted so a concurrent change of the language override cannot fail the comparison.
    private func isText(_ text: String, ofKey key: String) -> Bool {
        let entry = StringTable.entries[key]
        return text == entry?.en || text == entry?.ko
    }

    @Test func knownCodesGetTheirLocalizedText() {
        for (code, key) in Self.knownCodes {
            #expect(StringTable.entries[key] != nil, "\(key)")
            #expect(isText(ErrorText.message(for: PlopcutError(code, detail: "raw detail")), ofKey: key), "\(code)")
            #expect(isText(ErrorText.message(forCode: code), ofKey: key), "\(code)")
        }
    }

    @Test func anUnknownCodeNeverShowsItsLogDetail() {
        struct Other: Error {}
        for error: Error in [PlopcutError("something_new", detail: "/Users/me/secret: disk is on fire"),
                             PlopcutError("something_new", detail: ""), PlopcutError("something_new"), Other()] {
            #expect(isText(ErrorText.message(for: error), ofKey: "defaultError"))
        }
        #expect(isText(ErrorText.message(forCode: "something_new"), ofKey: "defaultError"))
    }

    // STA-78: the missing-permission and storage errors name a way forward, and their button label exists in both languages.
    @Test func recoverableErrorsOfferAButton() {
        #expect(ErrorRecovery.forCode("permission_missing") == .openAccessibilitySettings)
        for code in ["invalid_storage_folder", "storage_unwritable", "storage_unreadable", "settings_unwritable"] {
            #expect(ErrorRecovery.forCode(code) == .openPlopcutSettings, "\(code)")
        }
        for code in ["no_selected_text", "clipboard_empty", "clipboard_restore_failed", "something_new"] {
            #expect(ErrorRecovery.forCode(code) == nil, "\(code)")
        }
        for recovery in [ErrorRecovery.openAccessibilitySettings, .openPlopcutSettings] {
            #expect(StringTable.entries[recovery.titleKey] != nil)
        }
    }
}
