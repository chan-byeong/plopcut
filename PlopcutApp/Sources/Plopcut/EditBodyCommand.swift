import SwiftUI

/// "Edit" for the selected text drop with Cmd+E (spec 2.5, 2.6, checklist E-07). A menu command, so it works
/// wherever the Library shows a selected drop; it is off for image drops, in Settings, and while an editor is open.
struct EditBodyCommand: View {
    static let shortcut = KeyboardShortcut("e", modifiers: .command)
    let model: LibraryModel

    var body: some View {
        Button(DropAction.editBody.title) { model.beginBodyEdit() }
            .keyboardShortcut(Self.shortcut)
            .disabled(!model.canEditBody)
    }
}

/// The content editor's own keys: Cmd+Return for Done, Escape for Cancel (spec 2.6).
enum BodyEditorShortcuts {
    static let done = KeyboardShortcut(.return, modifiers: .command)
    static let cancel = KeyboardShortcut.cancelAction
}
