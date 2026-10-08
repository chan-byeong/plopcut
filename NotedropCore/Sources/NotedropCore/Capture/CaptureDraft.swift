import Foundation

/// A non-fatal problem found while capturing (spec section 6). Never blocks saving.
public struct CaptureWarning: Equatable, Sendable {
    public let code: String
    public init(_ code: String) { self.code = code }
}

/// What a capture produced, before the user confirms it in the Save Popup (spec 3.1, 3.5).
public struct CaptureDraft: Equatable, Sendable {
    public var type: DropType
    public var title: String
    public var text: String?
    public var imagePNG: Data?
    public var source: DropSource
    public var note: String?
    public var tags: [String]
    public var warnings: [CaptureWarning]

    public init(
        type: DropType, title: String, text: String? = nil, imagePNG: Data? = nil,
        source: DropSource = DropSource(), note: String? = nil, tags: [String] = [],
        warnings: [CaptureWarning] = []
    ) {
        self.type = type
        self.title = title
        self.text = text
        self.imagePNG = imagePNG
        self.source = source
        self.note = note
        self.tags = tags
        self.warnings = warnings
    }
}
