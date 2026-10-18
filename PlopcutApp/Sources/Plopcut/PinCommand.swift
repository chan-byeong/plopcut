import SwiftUI

/// "Pin" / "Unpin" for the selected drop with Shift+Cmd+P (spec 2.5, checklist L-18). Unlike Cmd+Backspace the
/// shortcut never edits text, so it works wherever the Library shows a selected drop, not only in the list.
struct PinCommand: View {
    static let shortcut = KeyboardShortcut("p", modifiers: [.command, .shift])
    let model: LibraryModel

    var body: some View {
        let drop = model.collection == .settings ? nil : model.selectedDrop
        Button(DropAction.pin(pinned: drop?.isPinned ?? false).title) {
            if let id = drop?.id { Task { await model.togglePin(id: id) } }
        }
        .keyboardShortcut(Self.shortcut)
        .disabled(drop == nil)
    }
}

/// The drop actions shared by the detail view's icon buttons and the list's context menu (spec 2.6).
enum DropAction: Equatable {
    case pin(pinned: Bool)
    case openSource
    case exportMarkdown
    case moveTrash

    var title: String {
        switch self {
        case .pin(let pinned): L10n.t(pinned ? "unpin" : "pin")
        case .openSource: L10n.t("openSource")
        case .exportMarkdown: L10n.t("exportMarkdown")
        case .moveTrash: L10n.t("moveTrash")
        }
    }

    var systemImage: String {
        switch self {
        case .pin(let pinned): pinned ? "pin.fill" : "pin"
        case .openSource: "arrow.up.right.square"
        case .exportMarkdown: "square.and.arrow.down"
        case .moveTrash: "trash"
        }
    }

    var shortcut: KeyboardShortcut? {
        switch self {
        case .pin: PinCommand.shortcut
        case .moveTrash: KeyboardShortcut(.delete, modifiers: .command)
        case .openSource, .exportMarkdown: nil
        }
    }

    /// The shortcut as the menu shows it, for the tooltip.
    private var shortcutText: String? {
        switch self {
        case .pin: "⇧⌘P"
        case .moveTrash: "⌘⌫"
        case .openSource, .exportMarkdown: nil
        }
    }

    /// "Name (Shortcut)", or just the name when the action has no shortcut.
    var tooltip: String { shortcutText.map { "\(title) (\($0))" } ?? title }
}
