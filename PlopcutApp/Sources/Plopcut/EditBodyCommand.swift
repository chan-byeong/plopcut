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

/// Done is Cmd+Return anywhere in the window while the editor is open. Escape cancels from the editor itself
/// (`BodyTextView.cancelOperation`), so Escape in the title or note field keeps its own meaning (spec 2.6).
enum BodyEditorShortcuts {
    static let done = KeyboardShortcut(.return, modifiers: .command)
}
