import SwiftUI

/// "Refresh Library" (Cmd+R) in the View menu. It replaced the toolbar button (spec 2.3). Text fields have no Cmd+R
/// binding, so the menu key equivalent does not take a key away from editing.
struct RefreshCommand: View {
    static let shortcut = KeyboardShortcut("r", modifiers: .command)
    let model: LibraryModel

    var body: some View {
        Button(L10n.t("refreshLibrary")) { Task { await model.reload() } }
            .keyboardShortcut(Self.shortcut)
    }
}
