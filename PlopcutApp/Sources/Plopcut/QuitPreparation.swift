import AppKit

/// The answer to "save the content draft before quitting?" (spec 2.6, E-16).
enum BodyDraftQuitChoice: Equatable { case save, discard, cancel }

/// Where quitting stands once the editor has done its work.
enum QuitPreparation: Equatable {
    /// Everything is written or deliberately discarded: the app may quit.
    case ready
    /// The user cancelled, or the content save failed and the open editor shows the error: the app stays open.
    case cancelled
    /// A title, note or tag autosave could not be written.
    case failed
}

/// Asks the quit question with a native alert: Save (Return), Don't Save, Cancel (Escape).
enum BodyDraftQuitAlert {
    @MainActor
    static func ask() async -> BodyDraftQuitChoice {
        // Quit can come from the menu bar menu while another app is in front; the question must be seen.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("quitBodyDraftTitle")
        alert.informativeText = L10n.t("quitBodyDraftBody")
        alert.addButton(withTitle: L10n.t("save"))
        alert.addButton(withTitle: L10n.t("dontSave"))
        alert.addButton(withTitle: L10n.t("cancel")).keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
}
