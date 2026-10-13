import AppKit
import SwiftUI
import PlopcutCore

/// The Save Popup content (spec 3.5): preview, source, note, tags, Save and Cancel.
struct SavePopupView: View {
    /// The content below the window's title bar for a draft without warnings, tag chips or many recent tags.
    /// Content that needs more height (warnings, tag chips, recent tags, an error) makes the window taller instead
    /// of being cut off (STA-67), up to `maxHeight`; past that the fields scroll and the buttons stay at the bottom.
    static let contentSize = CGSize(width: 430, height: 388)
    private static let previewHeight: CGFloat = 96

    @Bindable var model: SavePopupModel
    /// The tallest the content may get: the screen's visible height minus the title bar.
    var maxHeight: CGFloat = .infinity
    @FocusState private var tagFocused: Bool
    @State private var noteFocused = false
    @State private var noteControl = PopupNoteEditorControl()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                fields.padding(.horizontal, 16).padding(.top, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .slimScrollers()
            .layoutPriority(1)
            buttons.padding(.horizontal, 16)
        }
        .padding(.bottom, 16)
        .frame(width: Self.contentSize.width)
        .frame(minHeight: min(Self.contentSize.height, maxHeight), maxHeight: maxHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: tagFocused) { _, _ in CompositionMonitor.shared.reset() }
        .onChange(of: model.errorMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(alignment: .leading, spacing: 6) {
                preview
                source
            }
            warnings
            noteField
            tagField
            if let message = model.errorMessage {
                Text(message).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.t(model.selectedType == .image ? "saveImage" : "saveText")).font(.headline).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
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
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(L10n.t("image"))
        } else {
            ScrollView {
                Text(model.draft.text ?? "")
                    .font(.body).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(8)
            }
            .slimScrollers()
            .frame(height: Self.previewHeight)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var source: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(L10n.t("source")).font(.caption).foregroundStyle(.secondary)
            Text(model.sourceSummary).font(.callout).lineLimit(2).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var warnings: some View {
        let texts = model.draft.warnings.compactMap(Self.warningText)
        if !texts.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(texts, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("note")).font(.callout.weight(.semibold)).accessibilityHidden(true)
            PopupNoteEditor(
                text: $model.note, placeholder: L10n.t("optionalNote"), accessibilityLabel: L10n.t("note"),
                control: noteControl, onFocusChange: { focused in
                    noteFocused = focused
                    CompositionMonitor.shared.reset()
                }
            )
            .frame(height: 52).padding(4)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(noteFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: noteFocused ? 2 : 1))
        }
    }

    private var tagField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("tags")).font(.callout.weight(.semibold)).accessibilityHidden(true)
            HStack {
                TextField(L10n.t("tagPlaceholder"), text: $model.tagInput)
                    .focused($tagFocused)
                    .onSubmit { register() }
                    .onChange(of: model.tagInput) { old, value in
                        if !value.isEmpty { model.tagMessage = nil }
                        // Same rule as the detail pane: a typed comma registers, a pasted list registers.
                        let pasted = value.count - old.count > 1
                        if value.hasSuffix(",") || (pasted && value.contains(",")) { register() }
                    }
                    .accessibilityLabel(L10n.t("tags"))
                Button(L10n.t("addTag")) { register() }
                    .disabled(model.tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message = model.tagMessage { Text(message).font(.caption).foregroundStyle(.orange) }
            if !model.tags.isEmpty {
                FlowLayout {
                    ForEach(model.tags, id: \.self) { tag in
                        Button { model.removeTag(tag); tagFocused = true } label: {
                            Label("#\(tag)", systemImage: "xmark").labelStyle(.titleAndIcon).font(.caption)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel("\(L10n.t("removeTag")) #\(tag)")
                    }
                }
            }
            let suggestions = model.recentTags.filter { !model.tags.contains($0) }
            if !suggestions.isEmpty {
                Text(L10n.t("recentTags")).font(.caption).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(suggestions, id: \.self) { tag in
                        Button("#\(tag)") { model.addRecentTag(tag) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
        HStack {
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

    /// Enter and comma register tags, but not the key that only commits an input-method composition (spec I-01).
    private func register() {
        if CompositionMonitor.shared.shouldIgnoreRegistration { return }
        model.registerTagInput()
        tagFocused = true
    }
}
