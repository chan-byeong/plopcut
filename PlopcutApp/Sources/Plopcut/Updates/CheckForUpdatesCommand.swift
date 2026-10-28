import SwiftUI

/// "Check for Updates" in the app menu, below About (PLO-118). Left out when the build has no updater.
struct CheckForUpdatesCommand: View {
    let updates: UpdateModel

    var body: some View {
        if updates.isAvailable {
            Button(L10n.t("checkForUpdates")) { updates.check() }
                .disabled(!updates.canCheck)
        }
    }
}
