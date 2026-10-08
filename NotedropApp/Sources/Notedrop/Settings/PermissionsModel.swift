import AppKit
import Observation

enum PermissionItem: CaseIterable, Sendable {
    case accessibility, clipboard, automation
}

enum PermissionStatus: Sendable {
    case granted, missing, unknown
}

/// The OS questions behind the Permissions section. Faked in tests.
protocol PermissionChecking: Sendable {
    func accessibilityTrusted() -> Bool
    /// `nil` when the pasteboard state cannot be determined.
    func clipboardReadable() -> Bool?
}

struct SystemPermissionChecker: PermissionChecking {
    func accessibilityTrusted() -> Bool { AXIsProcessTrusted() }

    func clipboardReadable() -> Bool? {
        // NSPasteboard has no permission query. Text on the board that cannot be read means access is denied;
        // an empty or non-text board says nothing about access, so it stays unknown (checklist A-02).
        let board = NSPasteboard.general
        guard board.types?.contains(.string) == true else { return nil }
        return board.string(forType: .string) != nil
    }
}

/// Status of the three permissions shown in Settings (spec 2.6, checklist A-01..A-04). Automation cannot be queried
/// without prompting, so it is always `unknown`; macOS asks the first time the Chrome URL is read.
@MainActor
@Observable
final class PermissionsModel {
    private(set) var accessibility: PermissionStatus
    private(set) var clipboard: PermissionStatus

    private let checker: PermissionChecking
    private let openURL: (URL) -> Void

    init(checker: PermissionChecking = SystemPermissionChecker(), openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.checker = checker
        self.openURL = openURL
        accessibility = Self.accessibilityStatus(checker)
        clipboard = Self.clipboardStatus(checker)
    }

    /// Re-reads the OS state, e.g. when the user returns from System Settings.
    func refresh() {
        accessibility = Self.accessibilityStatus(checker)
        clipboard = Self.clipboardStatus(checker)
    }

    func status(of item: PermissionItem) -> PermissionStatus {
        switch item {
        case .accessibility: accessibility
        case .clipboard: clipboard
        case .automation: .unknown
        }
    }

    func offersSystemSettings(for item: PermissionItem) -> Bool {
        item == .accessibility && accessibility == .missing
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            openURL(url)
        }
    }

    private static func accessibilityStatus(_ checker: PermissionChecking) -> PermissionStatus {
        checker.accessibilityTrusted() ? .granted : .missing
    }

    private static func clipboardStatus(_ checker: PermissionChecking) -> PermissionStatus {
        switch checker.clipboardReadable() {
        case true?: .granted
        case false?: .missing
        case nil: .unknown
        }
    }

    // MARK: Text (N-04)

    static func itemKey(_ item: PermissionItem) -> String {
        switch item {
        case .accessibility: "accessibility"
        case .clipboard: "clipboard"
        case .automation: "automation"
        }
    }

    static func statusKey(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: "granted"
        case .missing: "missing"
        case .unknown: "permissionUnknown"
        }
    }

    static func detailKey(_ item: PermissionItem, _ status: PermissionStatus) -> String {
        switch (item, status) {
        case (_, .unknown): "permissionUnknownDetail"
        case (.accessibility, .granted): "permissionAccessibilityGranted"
        case (.accessibility, .missing): "permissionAccessibilityMissing"
        case (.clipboard, .granted): "permissionClipboardGranted"
        case (.clipboard, .missing): "permissionClipboardMissing"
        case (.automation, .granted): "permissionAutomationGranted"
        case (.automation, .missing): "permissionAutomationMissing"
        }
    }
}
