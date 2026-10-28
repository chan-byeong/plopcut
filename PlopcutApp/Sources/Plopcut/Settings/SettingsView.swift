import PlopcutCore
import SwiftUI

/// The Settings screen (spec 2.6). Storage folder, permissions and the shortcut join it in later tickets.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    @Environment(UpdateModel.self) private var updates

    var body: some View {
        Form {
            StorageFolderSection()
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
            PermissionsSection()
            Section(L10n.t("about")) {
                // App icon, name and version on one line (spec 4, U-06).
                HStack(spacing: Spacing.s) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage()).resizable().frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    Text("Plopcut").font(.headline)
                    Text(L10n.t("aboutVersion", ["version": model.appVersion])).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                if updates.isAvailable {
                    // Sparkle keeps this choice in the app's defaults; settings.json does not change (PLO-118).
                    Toggle(isOn: Binding(get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) })) {
                        Text(L10n.t("checkUpdatesAutomatically"))
                        Text(L10n.t("checkUpdatesAutomaticallyHelp"))
                    }
                    Button(L10n.t("checkForUpdates")) { updates.check() }
                        .disabled(!updates.canCheck)
                }
                Button(L10n.t("showLogInFinder")) { AppLog.revealInFinder() }
            }
            if let message = model.errorMessage {
                FeedbackText(message, kind: .error)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { updates.refresh() }
    }
}
