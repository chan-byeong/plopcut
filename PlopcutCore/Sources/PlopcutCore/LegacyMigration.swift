import Foundation

/// Moves the folders the app used under its former name, Notedrop, to their plopcut locations (STA-85).
///
/// Runs once at launch, before settings and the log are opened. A folder is renamed only when its plopcut
/// counterpart does not exist, so nothing is ever overwritten or merged. A custom storage folder is never touched.
/// Failures are returned, never thrown: the app keeps working on whatever paths are left.
public struct LegacyMigration: Sendable {
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Returns the errors that stopped a step; an empty array means everything that needed moving was moved.
    @discardableResult
    public func run() -> [PlopcutError] {
        var errors: [PlopcutError] = []
        for step in [moveSettingsFolder, moveStorageFolder, moveLogFolder] {
            do { try step() } catch { errors.append((error as? PlopcutError) ?? PlopcutError("unknown")) }
        }
        return errors
    }

    // MARK: Paths

    private func folder(_ relative: String) -> URL { home.appendingPathComponent(relative, isDirectory: true) }
    private var legacySupport: URL { folder("Library/Application Support/Notedrop") }
    private var support: URL { folder("Library/Application Support/plopcut") }
    private var legacyStorage: URL { folder("Documents/Notedrop") }
    private var storage: URL { folder("Documents/plopcut") }
    private var legacyLogs: URL { folder("Library/Logs/Notedrop") }
    private var logs: URL { folder("Library/Logs/plopcut") }

    // MARK: Steps

    private func moveSettingsFolder() throws {
        guard isDirectory(legacySupport), !exists(support) else { return }
        try move(legacySupport, to: support, code: "settings_unwritable")
    }

    private func moveStorageFolder() throws {
        guard isDirectory(legacyStorage), !exists(storage) else { return }
        let settingsFile = support.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: settingsFile, defaultStorageFolder: storage)
        let hasSettings = exists(settingsFile)
        if hasSettings {
            let current = try store.read().storageFolderPath
            guard URL(fileURLWithPath: current).standardizedFileURL.path == legacyStorage.standardizedFileURL.path else { return }
        }
        try move(legacyStorage, to: storage, code: "storage_unwritable")
        guard hasSettings else { return }
        do {
            _ = try store.update(SettingsUpdate(storageFolderPath: storage.path))
        } catch {
            try? FileManager.default.moveItem(at: storage, to: legacyStorage)
            throw error
        }
    }

    private func moveLogFolder() throws {
        guard isDirectory(legacyLogs), !exists(logs) else { return }
        try move(legacyLogs, to: logs, code: "log_unwritable")
        for suffix in ["", ".1"] {
            let old = logs.appendingPathComponent("notedrop.log\(suffix)")
            if exists(old) { try move(old, to: logs.appendingPathComponent("plopcut.log\(suffix)"), code: "log_unwritable") }
        }
    }

    // MARK: Helpers

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func move(_ source: URL, to destination: URL, code: String) throws {
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw PlopcutError(code, detail: error.localizedDescription)
        }
    }
}
