import AppKit
import SwiftUI

/// Settings section for the global selected-text shortcut (checklist C-06, C-08, D-06, D-12).
/// Click the field and press a key combination (STA-69); only Save changes the live shortcut and the file (STA-70).
struct ShortcutSection: View {
    /// Keeps the field from jumping in width while a shortcut is being recorded.
    private static let fieldMinWidth: CGFloat = 180
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
                FeedbackText(message, kind: .error)
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
        Text(fieldText)
            .font(.system(.body, design: .monospaced))  // shortcut notation uses the fixed-width system font
            .foregroundStyle(model.isRecording && model.heldModifiers == nil ? .secondary : .primary)
            .lineLimit(1)
            .frame(minWidth: Self.fieldMinWidth)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .inputSurface(focused: model.isRecording)
            .contentShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
    }
}
