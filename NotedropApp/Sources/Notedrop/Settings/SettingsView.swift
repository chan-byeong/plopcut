import NotedropCore
import SwiftUI

/// The Settings screen (spec 2.6). Storage folder, permissions and the shortcut join it in later tickets.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section(L10n.t("general")) {
                Picker(L10n.t("theme"), selection: Binding(get: { model.theme }, set: { model.setTheme($0) })) {
                    Text(L10n.t("system")).tag(Theme.system)
                    Text(L10n.t("light")).tag(Theme.light)
                    Text(L10n.t("dark")).tag(Theme.dark)
                }
                .pickerStyle(.segmented)
            }
            Section(L10n.t("captureSection")) {
                Picker(L10n.t("captureConfirmation"),
                       selection: Binding(get: { model.captureMode }, set: { model.setCaptureMode($0) })) {
                    Text(L10n.t("modal")).tag(CaptureConfirmationMode.modal)
                    Text(L10n.t("instant")).tag(CaptureConfirmationMode.instant)
                }
                .pickerStyle(.radioGroup)
            }
            ShortcutSection()
            Section(L10n.t("about")) {
                LabeledContent(L10n.t("appVersion"), value: model.appVersion)
            }
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
