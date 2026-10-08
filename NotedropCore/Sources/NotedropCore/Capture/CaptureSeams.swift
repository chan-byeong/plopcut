import Foundation

/// Text and PNG image held by the pasteboard, restored together as one item (checklist P-09).
public struct ClipboardSnapshot: Equatable, Sendable {
    public var text: String?
    public var png: Data?
    public init(text: String? = nil, png: Data? = nil) {
        self.text = text
        self.png = png
    }
}

public protocol ClipboardAccess: Sendable {
    /// `nil` when the platform can't report it; callers then compare text instead (spec 3.1 step 5).
    var changeCount: Int? { get }
    func read() throws -> ClipboardSnapshot
    func write(_ snapshot: ClipboardSnapshot) throws
}

public protocol CopyShortcutSender: Sendable {
    func sendCopy() throws
}

/// Reads the selection through the accessibility API without touching the clipboard (checklist P-16).
public protocol SelectedTextReader: Sendable {
    func readSelection() -> String?
}

public struct SourceResult: Equatable, Sendable {
    public var source: DropSource
    public var warnings: [CaptureWarning]
    public init(source: DropSource = DropSource(), warnings: [CaptureWarning] = []) {
        self.source = source
        self.warnings = warnings
    }
}

/// Best-effort source metadata. Failures become warnings, never errors (checklist M-03).
public protocol SourceCollector: Sendable {
    func collect() async -> SourceResult
}
