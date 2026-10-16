import AppKit
import SwiftUI
import PlopcutCore

/// The Save Popup content (spec 3.5): preview, source, note, tags, Save and Cancel.
struct SavePopupView: View {
    /// The content below the window's title bar for a draft without warnings, tag chips or many recent tags.
    /// Content that needs more height (warnings, tag chips, recent tags, an error) makes the window taller instead
    /// of being cut off (STA-67), up to `maxHeight`; past that the fields scroll and the buttons stay at the bottom.
    static let contentSize = CGSize(width: 430, height: 390)
    private static let previewHeight: CGFloat = 96
    /// About two lines of body text: the popup note is for a quick remark.
    private static let noteHeight: CGFloat = 52

    @Bindable var model: SavePopupModel
    /// The tallest the content may get: the screen's visible height minus the title bar.
    var maxHeight: CGFloat = .infinity
    @FocusState private var tagFocused: Bool
    @State private var noteFocused = false
    @State private var noteControl = PopupNoteEditorControl()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ScrollView {
                fields.padding(.horizontal, Spacing.l).padding(.top, Spacing.xs)
            }
            .scrollBounceBehavior(.basedOnSize)
            .slimScrollers()
            .layoutPriority(1)
            buttons.padding(.horizontal, Spacing.l)
        }
        .padding(.bottom, Spacing.l)
        .frame(width: Self.contentSize.width)
        .frame(minHeight: min(Self.contentSize.height, maxHeight), maxHeight: maxHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.errorMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                preview
                source
            }
            warnings
            noteField
            tagField
            if let message = model.errorMessage {
                FeedbackText(message, kind: .error)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            BrandMarkView().frame(width: 16, height: 16)
            Text(L10n.t(model.selectedType == .image ? "saveImage" : "saveText")).font(.headline).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.s)
            if model.isMixed { typePicker }
        }
    }

    private var typePicker: some View {
        Picker(L10n.t("chooseType"), selection: $model.selectedType) {
            Text(L10n.t("text")).tag(DropType.text)
            Text(L10n.t("image")).tag(DropType.image)
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
    }

    @ViewBuilder private var preview: some View {
        if model.selectedType == .image, let image = model.previewImage {
            Image(nsImage: image)
                .resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: Self.previewHeight)
                .contentWell()
                .accessibilityLabel(L10n.t("image"))
        } else {
            ScrollView {
                Text(model.draft.text ?? "")
                    .font(.body).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(Spacing.s)
            }
            .slimScrollers()
            .frame(height: Self.previewHeight)
            .contentWell()
        }
    }

    private var source: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(L10n.t("source")).font(.caption).foregroundStyle(.secondary)
            // The source app's icon before the summary; none for an unknown source (spec 3.5).
            if let icon = SourceAppIcons.shared.icon(forAppNamed: model.draft.source.appName) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                    .accessibilityHidden(true)
            }
            Text(model.sourceSummary).font(.callout).lineLimit(2).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var warnings: some View {
        let texts = model.draft.warnings.compactMap(Self.warningText)
        if !texts.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(texts, id: \.self) { FeedbackText($0, kind: .warning) }
            }
        }
    }

    private static func warningText(_ warning: CaptureWarning) -> String? {
        switch warning.code {
        case "clipboard_restore_failed", "clipboard_backup_failed": L10n.t("clipboardRestoreFailed")
        case "metadata_failed", "chrome_url_failed": L10n.t("automationFailed")
        default: nil
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L10n.t("note")).font(.callout.weight(.semibold)).accessibilityHidden(true)
            PopupNoteEditor(
                text: $model.note, placeholder: L10n.t("optionalNote"), accessibilityLabel: L10n.t("note"),
                control: noteControl, onFocusChange: { focused in
                    noteFocused = focused
                    CompositionMonitor.shared.reset()
                }
            )
            .frame(height: Self.noteHeight).padding(Spacing.xs)
            .inputSurface(focused: noteFocused)
        }
    }

    private var tagField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L10n.t("tags")).font(.callout.weight(.semibold)).accessibilityHidden(true)
            TagEntryField(model: model, focused: $tagFocused)
            let suggestions = model.recentTags.filter { !model.tags.contains($0) }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(L10n.t("recentTags")).font(.caption).foregroundStyle(.secondary)
                    FlowLayout {
                        ForEach(suggestions, id: \.self) { tag in
                            Button(Formatting.tag(tag)) { model.addRecentTag(tag) }.chipStyle()
                        }
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
        HStack {
            Text(L10n.t("popupShortcutHint")).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            Spacer()
            Button(L10n.t("cancel")) { model.cancel() }.keyboardShortcut(.cancelAction)
            Button(L10n.t("save")) {
                // Cmd+Enter can arrive while a syllable is still being composed (checklist I-04).
                noteControl.commitComposition()
                Task { await model.submit() }
            }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.isSaving)
        }
    }
}
