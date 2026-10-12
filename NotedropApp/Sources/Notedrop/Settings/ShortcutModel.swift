import NotedropCore
import Observation

/// The selected-text shortcut setting. Recording a key combination only changes the pending choice; nothing reaches
/// the OS or the settings file until Save calls `apply` (checklist C-08, STA-70). `apply` is the whole change
/// (register, release, save); when it throws, the field goes back to the shortcut that is still working.
@MainActor
@Observable
final class ShortcutModel {
    /// The shortcut that is registered and saved.
    private(set) var saved: String
    /// A recorded combination waiting for Save. Nil when nothing was chosen.
    private(set) var draft: String?
    private(set) var isRecording = false
    /// Modifiers held during a recording, such as `Shift+Cmd+`.
    private(set) var heldModifiers: String?
    private(set) var errorMessage: String?
    /// True while `errorMessage` is a recording-only hint (needs modifier, unsupported key). Those end with the recording.
    private var errorIsRecordingHint = false
    private let applyChange: (String) throws -> Void

    init(initial: String, apply: @escaping (String) throws -> Void) {
        saved = initial
        applyChange = apply
    }

    var displayText: String { draft ?? saved }
    var hasUnsavedChange: Bool { draft != nil }

    func startRecording() {
        isRecording = true
        heldModifiers = nil
        errorMessage = nil
    }

    /// Ends the recording in progress only; a combination chosen earlier stays pending. Every way a recording ends
    /// (Esc, click, key window change, app switch, a recorded combination, the current shortcut) comes through here,
    /// so the recording-only hint goes with it. Other messages (registration failures) stay.
    func cancelRecording() {
        isRecording = false
        heldModifiers = nil
        if errorIsRecordingHint {
            errorMessage = nil
            errorIsRecordingHint = false
        }
    }

    func modifiersChanged(_ preview: String?) {
        guard isRecording else { return }
        heldModifiers = preview
    }

    func handle(_ outcome: ShortcutRecording.Outcome) {
        guard isRecording else { return }
        switch outcome {
        case .recorded(let text):
            draft = text
            errorMessage = nil
            cancelRecording()
        case .cancelled:
            cancelRecording()
        case .rejected(let reason):
            errorMessage = L10n.t(reason.messageKey)
            errorIsRecordingHint = true
        }
    }

    /// The registered hot key fired. Carbon consumes that key press, so while recording it means the user pressed the
    /// working shortcut: keep it, with nothing left to save. Returns true when the press was taken by the recorder and
    /// must not start a capture. (When nothing is registered, e.g. after `shortcut_rollback_failed`, the hot key
    /// cannot fire; the press reaches `handle` as an ordinary key and stays pending so it can be saved again.)
    func currentShortcutPressed() -> Bool {
        guard isRecording else { return false }
        discard()
        return true
    }

    /// Save: register the new shortcut, release the old one, then write settings, all at once.
    func apply() {
        cancelRecording()
        guard let draft else { return }
        self.draft = nil
        do {
            try applyChange(draft)
            saved = draft
            errorMessage = nil
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }

    /// Cancel, or leaving the Settings screen: forget the unsaved choice. The working shortcut was never touched.
    func discard() {
        cancelRecording()
        draft = nil
        errorMessage = nil
    }
}
