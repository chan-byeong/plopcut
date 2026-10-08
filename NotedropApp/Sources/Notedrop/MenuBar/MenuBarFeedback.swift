import Foundation

/// Menu bar items the app routes. Unknown ids are ignored (checklist T-02).
enum MenuBarAction: String {
    case saveClipboard = "save-clipboard"
    case openLibrary = "open-library"

    init?(id: String) { self.init(rawValue: id) }
}

/// Shows `Error` next to the menu bar icon for 900 ms, then puts the title and tooltip back (checklist T-03).
/// The status item and the timer are injected so the timing can be tested.
@MainActor
final class MenuBarFeedback {
    static let idleTooltip = "Notedrop"
    static let errorText = "Error"
    static let duration: Duration = .milliseconds(900)

    private let apply: (_ title: String?, _ tooltip: String) -> Void
    private let schedule: (Duration, @escaping @MainActor () -> Void) -> () -> Void
    private var cancelRestore: (() -> Void)?

    init(
        apply: @escaping (_ title: String?, _ tooltip: String) -> Void,
        schedule: @escaping (Duration, @escaping @MainActor () -> Void) -> () -> Void
    ) {
        self.apply = apply
        self.schedule = schedule
    }

    func showError() {
        cancelRestore?()
        apply(Self.errorText, Self.errorText)
        cancelRestore = schedule(Self.duration) { [weak self] in
            self?.cancelRestore = nil
            self?.apply(nil, Self.idleTooltip)
        }
    }
}
