import Foundation
import Observation

/// The in-app updater (PLO-118). Sparkle sits behind it so the menus and Settings are testable without the network.
@MainActor
protocol AppUpdater: AnyObject {
    /// False while a check or an update is already in progress.
    var canCheckForUpdates: Bool { get }
    /// Stored by the updater itself in the app's defaults, not in settings.json.
    var automaticallyChecksForUpdates: Bool { get set }
    /// Called when `canCheckForUpdates` changes.
    var onCanCheckChange: (() -> Void)? { get set }
    /// Shows the updater's own window: checking, up to date, or the new version with its notes.
    func checkForUpdates()
}

/// What the menus and Settings show about updates. Without an updater (a build with no feed or key, such as
/// `swift run`), the update items are left out.
@MainActor
@Observable
final class UpdateModel {
    @ObservationIgnored private let updater: AppUpdater?
    private(set) var canCheck: Bool
    private(set) var automaticChecks: Bool

    init(updater: AppUpdater?) {
        self.updater = updater
        canCheck = updater?.canCheckForUpdates ?? false
        automaticChecks = updater?.automaticallyChecksForUpdates ?? false
        updater?.onCanCheckChange = { [weak self] in
            guard let self, let updater = self.updater else { return }
            canCheck = updater.canCheckForUpdates
        }
    }

    var isAvailable: Bool { updater != nil }

    func check() {
        guard let updater, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    /// Sparkle keeps the choice in the app's defaults, which can change outside Settings, so Settings reads it on appear.
    func refresh() {
        guard let updater else { return }
        canCheck = updater.canCheckForUpdates
        automaticChecks = updater.automaticallyChecksForUpdates
    }

    func setAutomaticChecks(_ on: Bool) {
        guard let updater else { return }
        updater.automaticallyChecksForUpdates = on
        automaticChecks = updater.automaticallyChecksForUpdates
    }
}
