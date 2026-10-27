import AppKit
import PlopcutCore
import SwiftUI

/// A floating panel's content (spec 2.8): the body, a divider, then the note. It reads the drop from the Library on
/// every change, so edits made there show here.
struct FloatingPanelView: View {
    let model: LibraryModel
    let id: String
    /// Laid out at full height without scrolling, to measure the height the panel opens at.
    var measuring = false

    private var drop: Drop? { model.drops.first { $0.id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let drop {
                content(of: drop)
                Divider()
                noteSection(drop.note)
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

    /// Read-only until PLO-114 makes it the shared note editor.
    private func noteSection(_ note: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L10n.t("note")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(note ?? L10n.t("noNote"))
                .foregroundStyle(note == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s)
                .contentWell()
                .accessibilityLabel(L10n.t("note"))
                .accessibilityValue(note ?? "")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
