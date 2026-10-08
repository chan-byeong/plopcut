import Foundation

/// Decides whether a storage folder can hold drops (spec 4). A folder that does not exist yet is fine when it can
/// still be created, because `DropStore` creates `drops/` on the first save.
public enum StorageFolderCheck {
    /// `nil` when saving can proceed; otherwise the reason it cannot.
    public static func problem(for root: URL, fileManager: FileManager = .default) -> NotedropError? {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { return NotedropError("invalid_storage_folder", detail: root.path) }
            return fileManager.isWritableFile(atPath: root.path) ? nil : NotedropError("storage_unwritable", detail: root.path)
        }
        // Walk up to the nearest folder that exists; the missing part is created below it.
        var ancestor = root.deletingLastPathComponent()
        while !fileManager.fileExists(atPath: ancestor.path, isDirectory: &isDirectory) {
            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestor.path { return NotedropError("storage_unwritable", detail: root.path) }
            ancestor = parent
        }
        guard isDirectory.boolValue else { return NotedropError("invalid_storage_folder", detail: root.path) }
        return fileManager.isWritableFile(atPath: ancestor.path) ? nil : NotedropError("storage_unwritable", detail: root.path)
    }

    public static func ensureUsable(_ root: URL, fileManager: FileManager = .default) throws {
        if let problem = problem(for: root, fileManager: fileManager) { throw problem }
    }

    /// Checks the folder and creates it when it is missing.
    public static func prepare(_ root: URL, fileManager: FileManager = .default) throws {
        try ensureUsable(root, fileManager: fileManager)
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw NotedropError("storage_unwritable", detail: error.localizedDescription)
        }
    }
}
