import Foundation

/// Moves a folder to the Trash. Injected so tests can simulate success and failure.
public protocol TrashMover: Sendable {
    func trash(_ url: URL) throws
}

public struct SystemTrashMover: TrashMover {
    public init() {}
    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

/// Fields to change on an existing drop. `nil` leaves the field as it is.
public struct DropUpdate: Sendable {
    public var title: String?
    public var tags: [String]?
    public var note: String?
    public var text: String?

    public init(title: String? = nil, tags: [String]? = nil, note: String? = nil, text: String? = nil) {
        self.title = title; self.tags = tags; self.note = note; self.text = text
    }
}

/// Slots written by concurrent scan workers, one per folder, so results keep directory order.
private enum ScanSlot: Sendable {
    case read(Drop, [ScanWarning])
    case skipped(ScanWarning)
}

private final class ScanResults: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [ScanSlot?]

    init(count: Int) { slots = Array(repeating: nil, count: count) }

    func set(_ index: Int, _ result: ScanSlot) {
        lock.lock(); defer { lock.unlock() }
        slots[index] = result
    }

    var values: [ScanSlot?] {
        lock.lock(); defer { lock.unlock() }
        return slots
    }
}

/// Reads and writes drop folders under `{root}/drops` (spec section 1).
public struct DropStore: Sendable {
    public let root: URL
    private let clock: @Sendable () -> Date
    private let trash: TrashMover

    public init(root: URL, clock: @escaping @Sendable () -> Date = { Date() }, trash: TrashMover = SystemTrashMover()) {
        self.root = root
        self.clock = clock
        self.trash = trash
    }

    private var dropsURL: URL { root.appendingPathComponent("drops", isDirectory: true) }
    private var fileManager: FileManager { .default }

    // MARK: Scan

    public func scan() throws -> DropScan {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dropsURL.path, isDirectory: &isDirectory) else {
            return DropScan(drops: [], warnings: [])
        }
        guard isDirectory.boolValue else { throw NotedropError("storage_unreadable", detail: dropsURL.path) }
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(at: dropsURL, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            throw NotedropError("storage_unreadable", detail: error.localizedDescription)
        }

        // Folders are read concurrently: the scan is bound by file latency, not CPU (STA-80 measurements).
        // Follows symlinks, like legacy `is_dir` and `existingFolder`, so a linked drop folder is listed.
        let folders = entries.filter { entry in
            var entryIsDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: entry.path, isDirectory: &entryIsDirectory) && entryIsDirectory.boolValue
        }
        let results = ScanResults(count: folders.count)
        DispatchQueue.concurrentPerform(iterations: folders.count) { index in
            let entry = folders[index]
            do {
                let (drop, dropWarnings) = try readFolder(entry)
                results.set(index, .read(drop, dropWarnings))
            } catch {
                results.set(index, .skipped(ScanWarning(code: "drop_scan_skipped", message: "\(entry.lastPathComponent): \(error)")))
            }
        }
        var drops: [Drop] = []
        var warnings: [ScanWarning] = []
        for result in results.values {
            switch result {
            case .read(let drop, let dropWarnings):
                drops.append(drop)
                warnings += dropWarnings
            case .skipped(let warning):
                warnings.append(warning)
            case nil:
                break
            }
        }
        drops.sort { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
        return DropScan(drops: drops, warnings: warnings)
    }

    private func readFolder(_ folder: URL) throws -> (Drop, [ScanWarning]) {
        let meta = try JSONDecoder().decode(DropMetadata.self, from: Data(contentsOf: folder.appendingPathComponent("drop.json")))
        var warnings: [ScanWarning] = []
        func warn(_ code: String, _ file: String) {
            warnings.append(ScanWarning(code: code, message: "\(folder.lastPathComponent)/\(file)"))
        }

        var drop = Drop(
            id: meta.id, type: meta.type, title: meta.title, source: meta.source, tags: meta.tags,
            createdAt: meta.createdAt, updatedAt: meta.updatedAt)

        switch meta.type {
        case .text:
            let url = folder.appendingPathComponent("content.md")
            if let content = try? String(contentsOf: url, encoding: .utf8) { drop.text = content } else { warn("drop_content_unreadable", "content.md") }
        case .image:
            let path = meta.imagePath ?? "image.png"
            drop.imagePath = path
            if let url = safeFileURL(path, in: folder), fileManager.isReadableFile(atPath: url.path) {
                drop.imageURL = url
            } else {
                warn("drop_image_unreadable", path)
            }
        case .mixed:
            drop.imagePath = meta.imagePath // legacy leaves mixed content unread (checklist D-02)
        }

        let noteURL = folder.appendingPathComponent("note.md")
        if fileManager.fileExists(atPath: noteURL.path) {
            if let note = try? String(contentsOf: noteURL, encoding: .utf8) {
                drop.note = note.trimmedNonEmpty == nil ? nil : note
            } else {
                warn("drop_note_unreadable", "note.md")
            }
        }
        return (drop, warnings)
    }

    /// A file inside `folder`, or `nil` if `name` would point elsewhere.
    private func safeFileURL(_ name: String, in folder: URL) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("..") else { return nil }
        return folder.appendingPathComponent(name)
    }

    // MARK: Save

    public func saveText(
        _ text: String, title: String?, source: DropSource, tags: [String], note: String?
    ) throws -> Drop {
        let body = Self.trimTrailingNewlines(text)
        guard body.trimmedNonEmpty != nil else { throw NotedropError("empty_text") }
        let resolved = Naming.inferTitle(
            explicit: title, windowTitle: source.windowTitle, appName: source.appName, text: body)
        return try create(type: .text, title: resolved, source: source, tags: tags, note: note) { folder in
            try write(Data(body.utf8), to: folder.appendingPathComponent("content.md"))
            return nil
        }
    }

    public func saveImage(
        _ png: Data, title: String?, source: DropSource, tags: [String], note: String?
    ) throws -> Drop {
        guard !png.isEmpty else { throw NotedropError("empty_image") }
        guard png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { throw NotedropError("invalid_image") }
        let resolved = Naming.inferTitle(
            explicit: title, windowTitle: source.windowTitle, appName: source.appName, fallback: "Image Drop")
        return try create(type: .image, title: resolved, source: source, tags: tags, note: note) { folder in
            try write(png, to: folder.appendingPathComponent("image.png"))
            return "image.png"
        }
    }

    private func create(
        type: DropType, title: String, source: DropSource, tags: [String], note: String?,
        writeContent: (URL) throws -> String?
    ) throws -> Drop {
        let now = clock()
        do {
            try fileManager.createDirectory(at: dropsURL, withIntermediateDirectories: true)
        } catch {
            throw NotedropError("storage_unwritable", detail: error.localizedDescription)
        }
        let baseID = Naming.dropID(date: now, title: title)
        var id = baseID
        var folder = dropsURL.appendingPathComponent(id, isDirectory: true)
        var attempt = 1
        while true {
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
                break
            } catch CocoaError.fileWriteFileExists {
                attempt += 1
                id = "\(baseID)-\(attempt)"
                folder = dropsURL.appendingPathComponent(id, isDirectory: true)
            } catch {
                throw NotedropError("storage_unwritable", detail: error.localizedDescription)
            }
        }
        do {
            let imagePath = try writeContent(folder)
            try write(Data((note ?? "").utf8), to: folder.appendingPathComponent("note.md"))
            let stamp = Timestamp.format(now)
            let meta = DropMetadata(
                id: id, type: type, title: title, imagePath: imagePath, source: source,
                tags: Tags.normalize(tags), createdAt: stamp, updatedAt: stamp)
            try writeMetadata(meta, in: folder)
            return try readFolder(folder).0
        } catch {
            try? fileManager.removeItem(at: folder)
            throw Self.asStorageError(error)
        }
    }

    // MARK: Update and delete

    public func update(id: String, _ change: DropUpdate) throws -> Drop {
        let folder = try existingFolder(id)
        let current: DropMetadata
        do {
            current = try JSONDecoder().decode(DropMetadata.self, from: Data(contentsOf: folder.appendingPathComponent("drop.json")))
        } catch {
            throw NotedropError("storage_unreadable", detail: error.localizedDescription)
        }

        // Validate everything before touching any file (checklist S-13).
        var meta = current
        if let title = change.title {
            guard let trimmed = title.trimmedNonEmpty else { throw NotedropError("invalid_title") }
            meta.title = trimmed
        }
        var newText: String?
        if let text = change.text, current.type == .text {
            let body = Self.trimTrailingNewlines(text)
            guard body.trimmedNonEmpty != nil else { throw NotedropError("empty_text") }
            newText = body
        }
        if let tags = change.tags { meta.tags = Tags.normalize(tags) }
        // A legacy image drop may omit `imagePath`; rewrite it with the default it was read with (S-01, S-20).
        if meta.type == .image, meta.imagePath == nil { meta.imagePath = "image.png" }
        meta.updatedAt = Timestamp.format(clock())

        do {
            if let note = change.note { try write(Data(note.utf8), to: folder.appendingPathComponent("note.md")) }
            if let newText { try write(Data(newText.utf8), to: folder.appendingPathComponent("content.md")) }
            try writeMetadata(meta, in: folder)
        } catch {
            throw Self.asStorageError(error)
        }
        return try readFolder(folder).0
    }

    public func delete(id: String) throws {
        let folder = try existingFolder(id)
        do { try trash.trash(folder) } catch { throw NotedropError("delete_failed", detail: error.localizedDescription) }
        if fileManager.fileExists(atPath: folder.path) { throw NotedropError("delete_failed", detail: "folder still exists") }
    }

    private func existingFolder(_ id: String) throws -> URL {
        guard Naming.isValidDropID(id) else { throw NotedropError("invalid_drop_id", detail: id) }
        let folder = dropsURL.appendingPathComponent(id, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NotedropError("drop_not_found", detail: id)
        }
        return folder
    }

    // MARK: Files

    private func writeMetadata(_ meta: DropMetadata, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try write(encoder.encode(meta), to: folder.appendingPathComponent("drop.json"))
    }

    private func write(_ data: Data, to url: URL) throws {
        do { try data.write(to: url, options: .atomic) } catch {
            throw NotedropError("storage_unwritable", detail: error.localizedDescription)
        }
    }

    private static func asStorageError(_ error: Error) -> NotedropError {
        (error as? NotedropError) ?? NotedropError("storage_unwritable", detail: error.localizedDescription)
    }

    static func trimTrailingNewlines(_ text: String) -> String {
        var scalars = Substring(text)
        while let last = scalars.last, last == "\n" || last == "\r" || last == "\r\n" { scalars = scalars.dropLast() }
        return String(scalars)
    }
}
