import Foundation

/// Menu bar items the app routes. Unknown ids are ignored (checklist T-02).
enum MenuBarAction: String {
    case saveClipboard = "save-clipboard"
    case openLibrary = "open-library"
    /// Shown only under a save failure (checklist T-05).
    case openSettings = "open-settings"
    /// The Floating Drops section, shown only while a panel is floating (spec 2.8).
    case hideAllFloating = "hide-all-floating"
    case showAllFloating = "show-all-floating"
    case closeAllFloating = "close-all-floating"

    init?(id: String) { self.init(rawValue: id) }
}

/// What the status item shows: the symbol in the dot's place, an optional movement, and the tooltip that is also the
/// accessibility name.
struct MenuBarAppearance: Equatable {
    enum Motion: Equatable {
        /// The dot falls into place (success).
        case drop
        /// The mark shakes left and right (failure).
        case shake
    }

    let accent: BrandMark.Accent
    let motion: Motion?
    let tooltip: String

    static let idle = MenuBarAppearance(accent: .dot, motion: nil, tooltip: MenuBarFeedback.idleTooltip)
}

/// The save feedback in the dot's place (spec 2.1, checklist T-03). Success drops the dot (200 ms), turns it into a
/// check, and puts the dot back about 1.1 s after the start. Failure shakes the mark (240 ms) and leaves an
/// exclamation mark until the menu opens; the menu then lists the reason (T-05). A success during a failure replaces
/// it. With Reduce Motion the symbols change at the same times without moving.
/// The status item, the timer and the Reduce Motion setting are injected so the states and timing can be tested.
@MainActor
final class MenuBarFeedback {
    nonisolated static let idleTooltip = "Plopcut"
    static let dropDuration: Duration = .milliseconds(200)
    static let shakeDuration: Duration = .milliseconds(240)
    /// From the start of the drop until the dot is back.
    static let savedDuration: Duration = .milliseconds(1100)

    /// The reason shown at the top of the menu while the exclamation mark is up.
    private(set) var failureReason: String?

    private let apply: (MenuBarAppearance) -> Void
    private let schedule: (Duration, @escaping @MainActor () -> Void) -> () -> Void
    private let reduceMotion: () -> Bool
    private var cancelPending: [() -> Void] = []

    init(
        apply: @escaping (MenuBarAppearance) -> Void,
        schedule: @escaping (Duration, @escaping @MainActor () -> Void) -> () -> Void,
        reduceMotion: @escaping () -> Bool
    ) {
        self.apply = apply
        self.schedule = schedule
        self.reduceMotion = reduceMotion
    }

    func showSaved() {
        reset()
        let motion: MenuBarAppearance.Motion? = reduceMotion() ? nil : .drop
        apply(MenuBarAppearance(accent: .dot, motion: motion, tooltip: L10n.t("menuBarSaved")))
        after(Self.dropDuration) { [weak self] in
            self?.apply(MenuBarAppearance(accent: .check, motion: nil, tooltip: L10n.t("menuBarSaved")))
        }
        after(Self.savedDuration) { [weak self] in self?.apply(.idle) }
    }

    func showError(reason: String) {
        reset()
        failureReason = reason
        let motion: MenuBarAppearance.Motion? = reduceMotion() ? nil : .shake
        apply(MenuBarAppearance(accent: .exclamation, motion: motion, tooltip: L10n.t("menuBarFailed")))
    }

    /// Called as the menu opens: returns the failure to list at the top of the menu, if any, and puts the dot back.
    func menuWillOpen() -> String? {
        guard let reason = failureReason else { return nil }
        reset()
        apply(.idle)
        return reason
    }

    private func reset() {
        cancelPending.forEach { $0() }
        cancelPending = []
        failureReason = nil
    }

    private func after(_ delay: Duration, _ work: @escaping @MainActor () -> Void) {
        cancelPending.append(schedule(delay, work))
    }
}
