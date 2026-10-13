import Foundation

/// Text and PNG image held by the pasteboard, restored together as one item (checklist P-09).
public struct ClipboardSnapshot: Equatable, Sendable {
    public var text: String?
    public var png: Data?
    /// An image is on the pasteboard but could not be turned into PNG (checklist K-03).
    public var imageUnreadable: Bool
    public init(text: String? = nil, png: Data? = nil, imageUnreadable: Bool = false) {
        self.text = text
        self.png = png
        self.imageUnreadable = imageUnreadable
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

/// The app a capture belongs to. It is resolved once when the capture starts and handed to both the source
/// collector and the selection reader, so they can never describe two different apps.
public struct CaptureTarget: Equatable, Sendable {
    public var processID: Int32
    public var name: String
    public var bundleID: String?
    public init(processID: Int32, name: String, bundleID: String? = nil) {
        self.processID = processID
        self.name = name
        self.bundleID = bundleID
    }
}

/// Reads the selection through the accessibility API without touching the clipboard (checklist P-16).
/// `target` is `nil` when no frontmost app could be determined; the reader then has nothing to read.
public protocol SelectedTextReader: Sendable {
    func readSelection(in target: CaptureTarget?) -> String?
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
    func collect(from target: CaptureTarget?) async -> SourceResult
}
