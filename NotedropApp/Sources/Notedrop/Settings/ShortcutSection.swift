import SwiftUI

/// Settings section for the global selected-text shortcut (checklist C-06, C-08, D-06, D-12).
struct ShortcutSection: View {
    @Environment(ShortcutModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section(L10n.t("selectedTextShortcut")) {
            TextField(L10n.t("captureShortcut"), text: $model.text, prompt: Text(L10n.t("shortcutExample")))
                .onSubmit { model.apply() }
            Text(L10n.t("shortcutFormatHint")).font(.caption).foregroundStyle(.secondary)
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                Spacer()
                Button(L10n.t("save")) { model.apply() }
            }
        }
    }
}
