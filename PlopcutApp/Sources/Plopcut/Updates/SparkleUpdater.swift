import Foundation
import Sparkle

/// Sparkle's standard updater and its windows (PLO-118). It reads the feed from `SUFeedURL` and checks each update
/// against `SUPublicEDKey`; `scripts/make-app.sh` writes both only when a public key is configured.
@MainActor
final class SparkleUpdater: AppUpdater {
    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?
    var onCanCheckChange: (() -> Void)?

    /// Nil when the bundle has no feed or key: starting Sparkle without them shows an error alert at launch.
    init?(bundle: Bundle = .main) {
        guard Self.isConfigured(bundle.infoDictionary ?? [:]) else { return nil }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
            Task { @MainActor in self?.onCanCheckChange?() }
        }
    }

    static func isConfigured(_ info: [String: Any]) -> Bool {
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return !feed.isEmpty && !key.isEmpty
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
