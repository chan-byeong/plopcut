import Foundation
import NotedropCore
import Testing
@testable import Notedrop

@MainActor
@Suite struct ShortcutModelTests {
    @Test func startsWithTheStoredShortcut() {
        let model = ShortcutModel(initial: "Shift+Cmd+K", apply: { _ in })
        #expect(model.text == "Shift+Cmd+K")
        #expect(model.errorMessage == nil)
    }

    @Test func applyPassesTheTypedTextAndClearsAnEarlierError() throws {
        var applied: [String] = []
        var fail = true
        let model = ShortcutModel(initial: "Shift+Cmd+C") { text in
            applied.append(text)
            if fail { throw NotedropError("shortcut_registration_failed") }
        }
        model.text = "Shift+Cmd+K"
        model.apply()
        #expect(model.errorMessage != nil)
        fail = false
        model.text = "Shift+Cmd+K"  // the refused text was reverted, so the retry is typed again
        model.apply()
        #expect(applied == ["Shift+Cmd+K", "Shift+Cmd+K"])
        #expect(model.errorMessage == nil)
    }

    // The field must not keep a shortcut that was refused: the old one is still the working one.
    @Test func aRefusedShortcutRevertsTheFieldToTheWorkingOne() {
        let model = ShortcutModel(initial: "Shift+Cmd+C") { _ in throw NotedropError("shortcut_registration_failed") }
        model.text = "Shift+Cmd+K"
        model.apply()
        #expect(model.text == "Shift+Cmd+C")
    }

    @Test func aSavedShortcutBecomesTheWorkingOne() {
        let model = ShortcutModel(initial: "Shift+Cmd+C", apply: { _ in })
        model.text = "Shift+Cmd+K"
        model.apply()
        model.text = "garbage"
        model.revert()
        #expect(model.text == "Shift+Cmd+K")
    }

    @Test func shortcutErrorsHaveDedicatedLocalizedMessages() {
        let fallback = ErrorText.message(forCode: "something_else")
        for code in ["invalid_selected_text_shortcut", "shortcut_registration_failed", "shortcut_rollback_failed"] {
            #expect(ErrorText.message(forCode: code) != fallback, "\(code)")
        }
    }

    @Test func formatHintNoLongerMentionsTheImplementation() {
        #expect(!L10n.t("shortcutFormatHint").contains("Tauri"))
    }
}
