import Foundation

public enum DropType: String, Codable, Sendable {
    case text, image, mixed
}

/// A text drop's chosen format (spec 1.2 `format`, PLO-101). `nil` on a drop means automatic detection.
public enum DropFormat: String, Codable, Sendable, CaseIterable {
    case plain, markdown, code
}

public struct DropSource: Equatable, Codable, Sendable {
    public var appName: String?
    public var windowTitle: String?
    public var url: String?
    public var filePath: String?

    public init(appName: String? = nil, windowTitle: String? = nil, url: String? = nil, filePath: String? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.filePath = filePath
    }

    private enum CodingKeys: String, CodingKey { case appName, windowTitle, url, filePath }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        windowTitle = try c.decodeIfPresent(String.self, forKey: .windowTitle)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        filePath = try c.decodeIfPresent(String.self, forKey: .filePath)
    }

    /// Always writes all four keys, using `null` for missing values (checklist S-01).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(appName, forKey: .appName)
        try c.encode(windowTitle, forKey: .windowTitle)
        try c.encode(url, forKey: .url)
        try c.encode(filePath, forKey: .filePath)
    }
}

/// A drop as loaded into memory: metadata plus the content of its side files.
public struct Drop: Equatable, Identifiable, Sendable {
    public var id: String
    public var type: DropType
    public var title: String
    public var text: String?
    public var imagePath: String?
    /// Absolute location of a readable image file, when there is one.
    public var imageURL: URL?
    public var source: DropSource
    /// `nil` when `note.md` is missing or only whitespace.
    public var note: String?
    public var tags: [String]
    public var createdAt: String
    public var updatedAt: String
    /// The user's format choice; `nil` means automatic detection (PLO-101).
    public var format: DropFormat?
    /// Only set when `format == .code`.
    public var codeLanguage: String?

    public init(
        id: String, type: DropType, title: String, text: String? = nil, imagePath: String? = nil,
        imageURL: URL? = nil, source: DropSource = DropSource(), note: String? = nil, tags: [String] = [],
        createdAt: String, updatedAt: String, format: DropFormat? = nil, codeLanguage: String? = nil
    ) {
        self.id = id; self.type = type; self.title = title; self.text = text
        self.imagePath = imagePath; self.imageURL = imageURL; self.source = source
        self.note = note; self.tags = tags; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.format = format; self.codeLanguage = format == .code ? codeLanguage : nil
    }
}

public struct DropScan: Equatable, Sendable {
    public var drops: [Drop]
    public var warnings: [ScanWarning]
}

/// On-disk `drop.json`. Reading tolerates missing optional keys; writing always emits the full contract.
struct DropMetadata: Codable {
    var id: String
    var type: DropType
    var title: String
    var imagePath: String?
    var source: DropSource
    var tags: [String]
    var createdAt: String
    var updatedAt: String
    var format: DropFormat?
    var codeLanguage: String?

    private enum CodingKeys: String, CodingKey {
        case id, type, title, text, imagePath, source, note, tags, createdAt, updatedAt
        case format, codeLanguage
    }

    init(id: String, type: DropType, title: String, imagePath: String?, source: DropSource,
         tags: [String], createdAt: String, updatedAt: String) {
        self.id = id; self.type = type; self.title = title; self.imagePath = imagePath
        self.source = source; self.tags = tags; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(DropType.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        source = try c.decodeIfPresent(DropSource.self, forKey: .source) ?? DropSource()
        tags = Tags.normalize(try c.decodeIfPresent([String].self, forKey: .tags) ?? [])
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        // A missing or unknown format means automatic detection, without a scan warning (spec 1.2, R-01).
        let format = (try? c.decodeIfPresent(String.self, forKey: .format)).flatMap { $0 }.flatMap(DropFormat.init(rawValue:))
        let language = (try? c.decodeIfPresent(String.self, forKey: .codeLanguage)).flatMap { $0 }
        setFormat(format, codeLanguage: language)
    }

    /// Keeps the language only for code, and treats an empty language as none.
    mutating func setFormat(_ format: DropFormat?, codeLanguage: String?) {
        self.format = format
        self.codeLanguage = format == .code ? codeLanguage?.trimmedNonEmpty : nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(title, forKey: .title)
        try c.encode(String?.none, forKey: .text)
        try c.encode(imagePath, forKey: .imagePath)
        try c.encode(source, forKey: .source)
        try c.encode(String?.none, forKey: .note)
        try c.encode(tags, forKey: .tags)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(format, forKey: .format)
        try c.encode(codeLanguage, forKey: .codeLanguage)
    }
}
