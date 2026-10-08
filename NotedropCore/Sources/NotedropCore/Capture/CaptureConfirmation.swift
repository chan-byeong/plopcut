import Foundation

/// What happens to a fresh draft, given the confirmation mode (spec 3.3, checklist P-11, P-12).
public enum CaptureConfirmation {
    public enum Route: Equatable, Sendable {
        case popup
        case saveNow
    }

    /// `instant` saves only text drafts; images and `mixed` drafts still need the popup to choose or preview.
    public static func route(mode: CaptureConfirmationMode, draftType: DropType) -> Route {
        mode == .instant && draftType == .text ? .saveNow : .popup
    }
}
