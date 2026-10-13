import Foundation

/// A failure with a stable machine-readable code (spec section 6) and optional detail for logs.
public struct PlopcutError: Error, Equatable, CustomStringConvertible, Sendable {
    public let code: String
    public let detail: String?

    public init(_ code: String, detail: String? = nil) {
        self.code = code
        self.detail = detail
    }

    public var description: String { detail.map { "\(code): \($0)" } ?? code }
}

/// A non-fatal problem found while reading a drop (spec section 1.7).
public struct ScanWarning: Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
