import AppKit
import SwiftUI

/// The Permissions section of the Settings screen. Re-reads the state whenever the app becomes active again.
struct PermissionsSection: View {
    @State private var model = PermissionsModel()

    var body: some View {
        Section(L10n.t("permissionStatus")) {
            ForEach(PermissionItem.allCases, id: \.self) { item in
                row(item)
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private func row(_ item: PermissionItem) -> some View {
        let status = model.status(of: item)
        return VStack(alignment: .leading, spacing: 4) {
            // The button stays outside the combined element so VoiceOver can still activate it.
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(L10n.t(PermissionsModel.itemKey(item))) {
                    Text(L10n.t(PermissionsModel.statusKey(status)))
                        .foregroundStyle(status == .missing ? Color.red : Color.secondary)
                }
                Text(L10n.t(PermissionsModel.detailKey(item, status)))
                    .font(.callout).foregroundStyle(.secondary)
                if item == .automation {
                    Text(L10n.t("permissionAutomationNote")).font(.callout).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if model.offersSystemSettings(for: item) {
                Button(L10n.t("openSystemSettings")) { model.openAccessibilitySettings() }
            }
        }
    }
}
