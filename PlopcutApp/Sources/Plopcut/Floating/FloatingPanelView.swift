import AppKit
import PlopcutCore
import SwiftUI

/// A floating panel's content (spec 2.8): the body, a divider, then the note. It reads the drop from the Library on
/// every change, so edits made there show here. The note shares the drop's editing state with the inspector.
struct FloatingPanelView: View {
    let model: LibraryModel
    let id: String
    /// Laid out at full height without scrolling, to measure the height the panel opens at.
    var measuring = false
    @State private var noteFocused = false
    /// About three lines of body text; a longer note scrolls inside the field.
    private static let noteHeight: CGFloat = 64

    private var drop: Drop? { model.drops.first { $0.id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let drop {
                content(of: drop)
                Divider()
                noteSection(drop)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: measuring ? nil : .infinity, alignment: .top)
    }

    /// A long text body scrolls; an image shrinks to fit instead (spec 2.8).
    @ViewBuilder private func content(of drop: Drop) -> some View {
        if let url = drop.imageURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: measuring ? nil : .infinity)
                .accessibilityLabel(L10n.t("image"))
        } else if drop.type == .image {
            Label(L10n.t("imagePreviewUnavailable"), systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary)
        } else if let text = drop.text {
            let body = RenderedBodyView(text: text, format: FormatDetection.resolve(drop), openLink: model.openLink)
                .environment(\.compactHeadings, true)
            if measuring {
                body
            } else {
                ScrollView { body }.slimScrollers().frame(maxHeight: .infinity)
            }
        }
    }

    /// The same note as the inspector's: typing here shows there and autosaves once (spec 2.7). Leaving the field
    /// saves at once; the panel's Escape does too and hands the keyboard back.
    private func noteSection(_ drop: Drop) -> some View {
        let editor: DropEditor = model.editor
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(L10n.t("note")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                SaveStatusView(state: editor.saveState(of: id)) { Task { await editor.retryNote(of: id) } }
            }
            PopupNoteEditor(
                text: Binding(get: { editor.note(of: drop) }, set: { editor.setNote($0, of: drop) }),
                placeholder: L10n.t("noNote"), accessibilityLabel: L10n.t("note"), focusOnAppear: false,
                onFocusChange: { focused in
                    noteFocused = focused
                    CompositionMonitor.shared.reset()
                    if !focused { Task { await editor.flushNote(of: id) } }
                })
                .frame(height: Self.noteHeight).padding(Spacing.xs)
                .inputSurface(focused: noteFocused)
        }
    }
}
