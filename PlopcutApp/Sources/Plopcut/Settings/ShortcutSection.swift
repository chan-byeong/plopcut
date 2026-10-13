import AppKit
import SwiftUI

/// Settings section for the global selected-text shortcut (checklist C-06, C-08, D-06, D-12).
/// Click the field and press a key combination (STA-69); only Save changes the live shortcut and the file (STA-70).
struct ShortcutSection: View {
    @Environment(ShortcutModel.self) private var model
    @State private var monitor = ShortcutKeyMonitor()

    var body: some View {
        Section(L10n.t("selectedTextShortcut")) {
            LabeledContent(L10n.t("shortcutField")) {
                Button { model.startRecording() } label: { field }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("selectedTextShortcut"))
                    .accessibilityValue(fieldText)
                    .accessibilityHint(L10n.t("shortcutRecordHint"))
            }
            // Leaving the Settings screen drops an unsaved choice; the working shortcut was never touched.
            .onAppear { monitor.install(model) }
            .onDisappear {
                monitor.remove()
                model.discard()
            }
            Text(L10n.t("shortcutRecordHint")).font(.caption).foregroundStyle(.secondary)
            if model.hasUnsavedChange {
                Text(L10n.t("shortcutUnsaved")).font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                Spacer()
                Button(L10n.t("cancel")) { model.discard() }
                    .disabled(!model.hasUnsavedChange && !model.isRecording)
                Button(L10n.t("save")) { model.apply() }
                    .disabled(!model.hasUnsavedChange)
            }
        }
    }

    private var fieldText: String {
        guard model.isRecording else { return model.displayText }
        return model.heldModifiers ?? L10n.t("shortcutRecording")
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Text(fieldText)
            .font(.system(.body, design: .monospaced))  // shortcut notation uses the fixed-width system font
            .foregroundStyle(model.isRecording && model.heldModifiers == nil ? .secondary : .primary)
            .lineLimit(1)
            .frame(minWidth: 180)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(shape.fill(Color(nsColor: .textBackgroundColor)))
            .overlay(shape.strokeBorder(
                model.isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                lineWidth: model.isRecording ? 2 : 1))
            .contentShape(shape)
    }
}
