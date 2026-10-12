import Foundation
import NotedropCore
import Testing
@testable import Notedrop

/// Records what reaches the OS and the settings file, so a test can tell "nothing happened yet" apart.
@MainActor
private final class Recorder: ShortcutRegistrar {
    final class Handle: ShortcutRegistration {
        let key: String
        let recorder: Recorder
        init(_ key: String, _ recorder: Recorder) { self.key = key; self.recorder = recorder }
        func unregister() { recorder.events.append("unregister \(key)") }
    }

    var events: [String] = []
    var failing: Set<String> = []
    var saveFails = false

    func register(_ shortcut: Shortcut) throws -> any ShortcutRegistration {
        if failing.contains(shortcut.key) {
            events.append("fail \(shortcut.key)")
            throw NotedropError("shortcut_registration_failed")
        }
        events.append("register \(shortcut.key)")
        return Handle(shortcut.key, self)
    }

    /// The model wired the way `CaptureRuntime` wires it: Save goes through the controller, which saves last.
    func model(_ initial: String = "Shift+Cmd+C") throws -> ShortcutModel {
        let controller = ShortcutController(registrar: self)
        try controller.start(initial)
        return ShortcutModel(initial: initial) { [unowned self] text in
            try controller.change(to: text) {
                if self.saveFails { throw NotedropError("settings_unwritable") }
                self.events.append("save \($0)")
            }
        }
    }
}

@MainActor
@Suite struct ShortcutModelTests {
    private func isText(_ text: String?, ofKey key: String) -> Bool {
        let entry = StringTable.entries[key]
        return text != nil && (text == entry?.en || text == entry?.ko)
    }

    @Test func startsWithTheStoredShortcutAndNothingPending() {
        let model = ShortcutModel(initial: "Shift+Cmd+K", apply: { _ in })
        #expect(model.displayText == "Shift+Cmd+K")
        #expect(!model.isRecording)
        #expect(!model.hasUnsavedChange)
        #expect(model.errorMessage == nil)
    }

    // MARK: STA-70: nothing changes before Save

    @Test func recordingAndChoosingAKeyNeitherRegistersNorSaves() throws {
        let recorder = Recorder()
        let model = try recorder.model()
        model.startRecording()
        model.modifiersChanged("Shift+Cmd+")
        model.handle(.rejected(.needsModifier))
        model.handle(.recorded("Shift+Cmd+K"))
        #expect(model.displayText == "Shift+Cmd+K")
        #expect(model.hasUnsavedChange)
        #expect(recorder.events == ["register C"])
    }

    @Test func saveRegistersTheNewShortcutReleasesTheOldOneAndSavesLast() throws {
        let recorder = Recorder()
        let model = try recorder.model()
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+K"))
        model.apply()
        #expect(recorder.events == ["register C", "register K", "unregister C", "save Shift+Cmd+K"])
        #expect(model.displayText == "Shift+Cmd+K")
        #expect(!model.hasUnsavedChange)
        #expect(model.errorMessage == nil)
    }

    @Test func cancellingTheRecordingKeepsTheWorkingShortcut() throws {
        let recorder = Recorder()
        let model = try recorder.model()
        model.startRecording()
        model.handle(.cancelled)
        #expect(!model.isRecording)
        #expect(model.displayText == "Shift+Cmd+C")
        #expect(!model.hasUnsavedChange)
        model.apply()  // nothing pending, so Save does nothing
        #expect(recorder.events == ["register C"])
    }

    /// Esc cancels only the recording in progress; a key chosen earlier stays pending until Save or Cancel.
    @Test func cancellingASecondRecordingKeepsTheEarlierChoice() {
        let model = ShortcutModel(initial: "Shift+Cmd+C", apply: { _ in })
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+K"))
        model.startRecording()
        model.handle(.cancelled)
        #expect(model.displayText == "Shift+Cmd+K")
    }

    /// The Cancel button and leaving the Settings screen both drop the unsaved choice.
    @Test func discardingDropsTheUnsavedChoiceWithoutTouchingTheShortcut() throws {
        let recorder = Recorder()
        let model = try recorder.model()
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+K"))
        model.startRecording()
        model.handle(.rejected(.unsupportedKey))
        model.discard()
        #expect(!model.isRecording)
        #expect(model.displayText == "Shift+Cmd+C")
        #expect(!model.hasUnsavedChange)
        #expect(model.errorMessage == nil)
        #expect(model.heldModifiers == nil)
        #expect(recorder.events == ["register C"])
    }

    // MARK: Recording (STA-69)

    @Test func heldModifiersAreShownOnlyWhileRecording() {
        let model = ShortcutModel(initial: "Shift+Cmd+C", apply: { _ in })
        model.modifiersChanged("Cmd+")
        #expect(model.heldModifiers == nil)
        model.startRecording()
        model.modifiersChanged("Cmd+")
        #expect(model.heldModifiers == "Cmd+")
        model.handle(.recorded("Cmd+K"))
        #expect(model.heldModifiers == nil)
    }

    @Test func aRejectedKeyExplainsWhyAndKeepsRecording() {
        let model = ShortcutModel(initial: "Shift+Cmd+C", apply: { _ in })
        model.startRecording()
        model.handle(.rejected(.needsModifier))
        #expect(model.isRecording)
        #expect(isText(model.errorMessage, ofKey: "shortcutNeedsModifier"))
        model.handle(.rejected(.unsupportedKey))
        #expect(isText(model.errorMessage, ofKey: "shortcutUnsupportedKey"))
        model.handle(.recorded("Shift+Cmd+K"))
        #expect(model.errorMessage == nil)
        #expect(!model.isRecording)
    }

    // STA-83: a recording-only hint must not outlive the recording, whichever way it ends.
    private func recordingWithHint() -> ShortcutModel {
        let model = ShortcutModel(initial: "Shift+Cmd+C", apply: { _ in })
        model.startRecording()
        model.handle(.rejected(.needsModifier))
        #expect(isText(model.errorMessage, ofKey: "shortcutNeedsModifier"))
        return model
    }

    @Test func escapeClearsTheRecordingHint() {
        let model = recordingWithHint()
        model.handle(.cancelled)
        #expect(!model.isRecording)
        #expect(model.errorMessage == nil)
    }

    @Test func externalEndsClearTheRecordingHint() {
        // Click elsewhere, key window change and app switch all reach the model as cancelRecording.
        let model = recordingWithHint()
        model.cancelRecording()
        #expect(model.errorMessage == nil)
        model.startRecording()
        model.handle(.rejected(.unsupportedKey))
        #expect(isText(model.errorMessage, ofKey: "shortcutUnsupportedKey"))
        model.cancelRecording()
        #expect(model.errorMessage == nil)
    }

    @Test func recordedCombinationClearsTheRecordingHint() {
        let model = recordingWithHint()
        model.handle(.recorded("Shift+Cmd+K"))
        #expect(model.errorMessage == nil)
    }

    @Test func pressingTheCurrentShortcutClearsTheRecordingHint() {
        let model = recordingWithHint()
        #expect(model.currentShortcutPressed())
        #expect(model.errorMessage == nil)
    }

    @Test func discardClearsTheRecordingHint() {
        let model = recordingWithHint()
        model.discard()
        #expect(model.errorMessage == nil)
    }

    @Test func registrationFailureSurvivesAndIsNotARecordingHint() {
        struct Boom: Error {}
        let model = ShortcutModel(initial: "Shift+Cmd+C", apply: { _ in throw Boom() })
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+K"))
        model.apply()
        let failure = model.errorMessage
        #expect(failure != nil)
        model.startRecording()
        model.cancelRecording()
        #expect(model.errorMessage == nil || model.errorMessage == failure)
    }

    @Test func keysArriveOnlyWhileRecording() {
        let model = ShortcutModel(initial: "Shift+Cmd+C", apply: { _ in })
        model.handle(.recorded("Shift+Cmd+K"))
        model.handle(.rejected(.needsModifier))
        #expect(model.displayText == "Shift+Cmd+C")
        #expect(model.errorMessage == nil)
    }

    /// The live hot key swallows its own key press, so the recorder hears it through the hot key instead. The press
    /// proves that shortcut is registered and working, so it means "keep it": nothing is left to save.
    @Test func pressingTheWorkingShortcutWhileRecordingKeepsItWithNothingToSave() {
        let model = ShortcutModel(initial: "Shift+Cmd+C", apply: { _ in Issue.record("must not apply") })
        #expect(!model.currentShortcutPressed())  // not recording: the press is a capture
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+K"))
        #expect(model.hasUnsavedChange)
        model.startRecording()
        model.handle(.rejected(.unsupportedKey))
        #expect(model.currentShortcutPressed())
        #expect(!model.isRecording)
        #expect(model.displayText == "Shift+Cmd+C")
        #expect(!model.hasUnsavedChange)
        #expect(model.errorMessage == nil)
        model.apply()
    }

    // MARK: Failures keep the working shortcut (STA-55)

    @Test func aConflictingShortcutIsRefusedAndTheFieldShowsTheWorkingOne() throws {
        let recorder = Recorder()
        let model = try recorder.model()
        recorder.failing = ["K"]
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+K"))
        model.apply()
        #expect(isText(model.errorMessage, ofKey: "shortcutRegistrationFailed"))
        #expect(model.displayText == "Shift+Cmd+C")
        #expect(!model.hasUnsavedChange)
        #expect(recorder.events == ["register C", "fail K"])
    }

    @Test func aRetryAfterARefusalClearsTheError() {
        var fail = true
        var applied: [String] = []
        let model = ShortcutModel(initial: "Shift+Cmd+C") { text in
            applied.append(text)
            if fail { throw NotedropError("shortcut_registration_failed") }
        }
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+K"))
        model.apply()
        #expect(model.errorMessage != nil)
        fail = false
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+J"))
        model.apply()
        #expect(applied == ["Shift+Cmd+K", "Shift+Cmd+J"])
        #expect(model.errorMessage == nil)
        #expect(model.displayText == "Shift+Cmd+J")
    }

    /// After `shortcut_rollback_failed` nothing is registered, so the hot key cannot fire and the press reaches the
    /// recorder as an ordinary key. Choosing the old keys again must stay pending and be savable.
    @Test func afterARollbackFailureTheOldKeysCanBeSavedAgain() throws {
        let recorder = Recorder()
        let model = try recorder.model()
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+K"))
        recorder.saveFails = true
        recorder.failing = ["C"]  // someone took the old shortcut meanwhile
        model.apply()
        #expect(isText(model.errorMessage, ofKey: "shortcutRollbackFailed"))
        #expect(model.displayText == "Shift+Cmd+C")

        recorder.saveFails = false
        recorder.failing = []
        model.startRecording()
        model.handle(.recorded("Shift+Cmd+C"))
        #expect(model.hasUnsavedChange)
        model.apply()
        #expect(Array(recorder.events.suffix(2)) == ["register C", "save Shift+Cmd+C"])
        #expect(!model.hasUnsavedChange)
        #expect(model.errorMessage == nil)
    }

    @Test func shortcutMessagesHaveBothLanguages() {
        let fallback = ErrorText.message(forCode: "something_else")
        for code in ["invalid_selected_text_shortcut", "shortcut_registration_failed", "shortcut_rollback_failed"] {
            #expect(ErrorText.message(forCode: code) != fallback, "\(code)")
        }
        for key in ["shortcutNeedsModifier", "shortcutUnsupportedKey", "shortcutRecordHint", "shortcutRecording",
                    "shortcutUnsaved", "shortcutField"] {
            #expect(StringTable.entries[key] != nil, "\(key)")
        }
    }

    @Test func formatHintNoLongerMentionsTheImplementation() {
        #expect(!L10n.t("shortcutFormatHint").contains("Tauri"))
    }
}
