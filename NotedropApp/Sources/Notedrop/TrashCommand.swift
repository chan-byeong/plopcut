import SwiftUI

extension FocusedValues {
    /// Set by the Library list while it has focus; `nil` everywhere else, which disables the menu item.
    @Entry var trashSelectedDrop: (() -> Void)?
}

/// "Move to Trash" with Cmd+Backspace (checklist L-12). A menu key equivalent is handled before the focused view
/// sees the key, so this is a menu command; it is only enabled while the list has focus, which leaves
/// Cmd+Backspace in the note and tag fields to delete text as usual.
struct TrashCommand: View {
    @FocusedValue(\.trashSelectedDrop) private var trash

    var body: some View {
        Button(L10n.t("moveTrash")) { trash?() }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(trash == nil)
    }
}
