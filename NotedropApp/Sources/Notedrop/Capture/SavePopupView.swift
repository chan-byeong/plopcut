import AppKit
import SwiftUI
import NotedropCore

/// The Save Popup content (spec 3.5): preview, source, note, tags, Save and Cancel.
struct SavePopupView: View {
    @Bindable var model: SavePopupModel
    @FocusState private var focus: Field?
    private enum Field { case note, tag }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t(model.selectedType == .image ? "saveImage" : "saveText")).font(.headline)
            if model.isMixed { typePicker }
            preview
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("source")).font(.caption).foregroundStyle(.secondary)
                Text(model.sourceSummary).font(.callout).lineLimit(2).textSelection(.enabled)
            }
            warnings
            noteField
            tagField
            if let message = model.errorMessage {
                Text(message).font(.callout).foregroundStyle(.red).accessibilityAddTraits(.isStaticText)
            }
            Spacer(minLength: 0)
            buttons
        }
        .padding(20)
        .frame(width: 430, height: 560)
        .onAppear { focus = .note }
    }

    private var typePicker: some View {
        Picker(L10n.t("chooseType"), selection: $model.selectedType) {
            Text(L10n.t("text")).tag(DropType.text)
            Text(L10n.t("image")).tag(DropType.image)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var preview: some View {
        if model.selectedType == .image, let image = model.previewImage {
            Image(nsImage: image)
                .resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 120)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(L10n.t("image"))
        } else {
            ScrollView {
                Text(model.draft.text ?? "")
                    .font(.body).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(8)
            }
            .frame(height: 120)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
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
            Text(L10n.t("note")).font(.headline)
            TextEditor(text: $model.note)
                .font(.body).frame(height: 70).scrollContentBackground(.hidden).padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(focus == .note ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: focus == .note ? 2 : 1))
                .overlay(alignment: .topLeading) {
                    if model.note.isEmpty { Text(L10n.t("optionalNote")).foregroundStyle(.secondary).padding(9).allowsHitTesting(false) }
                }
                .focused($focus, equals: .note)
                .accessibilityLabel(L10n.t("note"))
        }
    }

    private var tagField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("tags")).font(.headline)
            HStack {
                TextField(L10n.t("tagPlaceholder"), text: $model.tagInput)
                    .focused($focus, equals: .tag)
                    .onSubmit { register() }
                    .onChange(of: focus) { _, _ in CompositionMonitor.shared.reset() }
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
            FlowLayout {
                ForEach(model.tags, id: \.self) { tag in
                    Button { model.removeTag(tag); focus = .tag } label: {
                        Label("#\(tag)", systemImage: "xmark").labelStyle(.titleAndIcon).font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityLabel("\(L10n.t("removeTag")) #\(tag)")
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
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button(L10n.t("cancel")) { model.cancel() }.keyboardShortcut(.cancelAction)
            Button(L10n.t("save")) { Task { await model.submit() } }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.isSaving)
        }
    }

    /// Enter and comma register tags, but not the key that only commits an input-method composition (spec I-01).
    private func register() {
        if CompositionMonitor.shared.shouldIgnoreRegistration { return }
        model.registerTagInput()
        focus = .tag
    }
}
