import Foundation

/// What may be written to the support log. Every case carries only fixed vocabulary, numbers or an error code, so a
/// caller cannot put drop text, notes, titles, URLs, tags or paths into the log by accident (STA-80).
public enum LogEvent: Equatable, Sendable {
    case appStart(version: String, build: String, macOS: String)
    case error(code: String)
    case permission(item: String, status: String)

    /// The text after the timestamp. Free-form values are reduced to a safe token first.
    public var line: String {
        switch self {
        case let .appStart(version, build, macOS):
            "app_start version=\(Self.token(version)) build=\(Self.token(build)) macos=\(Self.token(macOS))"
        case let .error(code):
            "error code=\(Self.token(code))"
        case let .permission(item, status):
            "permission item=\(Self.token(item)) status=\(Self.token(status))"
        }
    }

    /// Keeps letters, digits and `._-` (at most 40 characters). Anything else, such as a sentence or a path, becomes
    /// `invalid`, so even an unexpected `code` string cannot carry user content.
    static func token(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !value.isEmpty, value.count <= 40, value.unicodeScalars.allSatisfy(allowed.contains) else { return "invalid" }
        return value
    }
}

/// The seam callers use. Implementations must never throw, crash or wait on the network.
public protocol EventLogging: Sendable {
    func log(_ event: LogEvent)
}

public extension EventLogging {
    /// Logs the code only. `detail` (paths, OS wording) and the message are never read.
    func log(error: Error) {
        log(.error(code: (error as? NotedropError)?.code ?? "unknown"))
    }
}

/// Discards everything; the default in tests.
public struct NullEventLog: EventLogging {
    public init() {}
    public func log(_ event: LogEvent) {}
}

/// Appends timestamped lines to a local file. When the file reaches `maxBytes` it becomes `<name>.1` (replacing the
/// older one) and a new file starts, so the log never exceeds about twice `maxBytes`. Local only; nothing is uploaded.
public final class FileEventLog: EventLogging, @unchecked Sendable {
    public static let defaultMaxBytes = 1_000_000

    /// `~/Library/Logs/Notedrop/notedrop.log`
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Notedrop/notedrop.log")
    }

    public let url: URL
    private let maxBytes: Int
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(url: URL = FileEventLog.defaultURL, maxBytes: Int = FileEventLog.defaultMaxBytes,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.maxBytes = maxBytes
        self.now = now
    }

    public var previousURL: URL { url.appendingPathExtension("1") }

    public func log(_ event: LogEvent) {
        let stamp = now().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeZone(separator: .omitted))
        guard let data = "\(stamp) \(event.line)\n".data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        append(data)
    }

    /// Any failure (no folder, read-only disk, full disk) drops the line silently; logging must not affect the app.
    private func append(_ data: Data) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? Int, size >= maxBytes {
                try? fm.removeItem(at: previousURL)
                try fm.moveItem(at: url, to: previousURL)
            }
            if !fm.fileExists(atPath: url.path) {
                guard fm.createFile(atPath: url.path, contents: nil) else { return }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }
}
