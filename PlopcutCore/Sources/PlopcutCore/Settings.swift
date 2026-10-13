import Foundation

public enum Theme: String, Sendable { case system, light, dark }
public enum CaptureConfirmationMode: String, Sendable { case modal, instant }

public struct PaneWidths: Equatable, Sendable {
    public static let sidebarRange = 180.0...320.0
    public static let libraryRange = 300.0...560.0

    public static let `default` = PaneWidths(sidebar: 220, library: 330)

    public var sidebar: Double
    public var library: Double

    public init(sidebar: Double, library: Double) {
        self.sidebar = min(max(sidebar, Self.sidebarRange.lowerBound), Self.sidebarRange.upperBound)
        self.library = min(max(library, Self.libraryRange.lowerBound), Self.libraryRange.upperBound)
    }
}

public struct AppSettings: Equatable, Sendable {
    public var storageFolderPath: String
    public var hasCompletedFirstRun: Bool
    public var theme: Theme
    public var captureConfirmationMode: CaptureConfirmationMode
    public var selectedTextShortcut: String
    public var paneWidths: PaneWidths
    public var recentTags: [String]
    public var updatedAt: String

    public init(
        storageFolderPath: String, hasCompletedFirstRun: Bool, theme: Theme,
        captureConfirmationMode: CaptureConfirmationMode, selectedTextShortcut: String,
        paneWidths: PaneWidths, recentTags: [String], updatedAt: String
    ) {
        self.storageFolderPath = storageFolderPath; self.hasCompletedFirstRun = hasCompletedFirstRun
        self.theme = theme; self.captureConfirmationMode = captureConfirmationMode
        self.selectedTextShortcut = selectedTextShortcut; self.paneWidths = paneWidths
        self.recentTags = recentTags; self.updatedAt = updatedAt
    }
}

/// Fields to change. `nil` leaves a field unchanged.
public struct SettingsUpdate: Sendable {
    public var storageFolderPath: String?
    public var hasCompletedFirstRun: Bool?
    public var theme: Theme?
    public var captureConfirmationMode: CaptureConfirmationMode?
    public var selectedTextShortcut: String?
    public var paneWidths: PaneWidths?
    public var recentTags: [String]?

    public init(
        storageFolderPath: String? = nil, hasCompletedFirstRun: Bool? = nil, theme: Theme? = nil,
        captureConfirmationMode: CaptureConfirmationMode? = nil, selectedTextShortcut: String? = nil,
        paneWidths: PaneWidths? = nil, recentTags: [String]? = nil
    ) {
        self.storageFolderPath = storageFolderPath; self.hasCompletedFirstRun = hasCompletedFirstRun
        self.theme = theme; self.captureConfirmationMode = captureConfirmationMode
        self.selectedTextShortcut = selectedTextShortcut; self.paneWidths = paneWidths; self.recentTags = recentTags
    }
}

/// Reads and atomically writes `settings.json` (spec section 1.8). Updates are serialized.
public final class SettingsStore: @unchecked Sendable {
    public static let defaultShortcut = "Shift+Cmd+C"

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/plopcut/settings.json")
    }

    public static var defaultStorageFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/plopcut", isDirectory: true)
    }

    private let fileURL: URL
    private let defaultStorageFolder: URL
    private let clock: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        fileURL: URL = SettingsStore.defaultFileURL, defaultStorageFolder: URL = SettingsStore.defaultStorageFolder,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.defaultStorageFolder = defaultStorageFolder
        self.clock = clock
    }

    /// Returns the settings, creating the file with defaults when it does not exist.
    public func read() throws -> AppSettings {
        lock.lock(); defer { lock.unlock() }
        return try readLocked()
    }

    public func update(_ change: SettingsUpdate) throws -> AppSettings {
        lock.lock(); defer { lock.unlock() }
        var settings = try readLocked()

        if let path = change.storageFolderPath {
            guard let trimmed = path.trimmedNonEmpty else { throw PlopcutError("invalid_storage_folder") }
            settings.storageFolderPath = trimmed
        }
        if let shortcut = change.selectedTextShortcut {
            _ = try Shortcut.parse(shortcut)
            settings.selectedTextShortcut = shortcut.trimmingCharacters(in: .whitespaces)
        }
        if let value = change.hasCompletedFirstRun { settings.hasCompletedFirstRun = value }
        if let value = change.theme { settings.theme = value }
        if let value = change.captureConfirmationMode { settings.captureConfirmationMode = value }
        if let value = change.paneWidths { settings.paneWidths = PaneWidths(sidebar: value.sidebar, library: value.library) }
        if let value = change.recentTags { settings.recentTags = Tags.limitedRecent(value) }
        settings.updatedAt = Timestamp.format(clock())

        try write(settings)
        return settings
    }

    // MARK: Private

    private func readLocked() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = AppSettings(
                storageFolderPath: defaultStorageFolder.path, hasCompletedFirstRun: false, theme: .system,
                captureConfirmationMode: .modal, selectedTextShortcut: Self.defaultShortcut,
                paneWidths: .default, recentTags: [], updatedAt: Timestamp.format(clock()))
            try write(defaults)
            return defaults
        }
        let data: Data
        do { data = try Data(contentsOf: fileURL) } catch {
            throw PlopcutError("settings_unreadable", detail: error.localizedDescription)
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PlopcutError("settings_invalid", detail: "not a JSON object")
        }
        return try parse(object)
    }

    private func parse(_ object: [String: Any]) throws -> AppSettings {
        func invalid(_ key: String) -> PlopcutError { PlopcutError("settings_invalid", detail: key) }
        guard let path = object["storageFolderPath"] as? String else { throw invalid("storageFolderPath") }
        guard let firstRun = object["hasCompletedFirstRun"] as? Bool else { throw invalid("hasCompletedFirstRun") }
        guard let themeName = object["theme"] as? String else { throw invalid("theme") }
        guard let updatedAt = object["updatedAt"] as? String else { throw invalid("updatedAt") }

        var mode = CaptureConfirmationMode.modal
        if let raw = object["captureConfirmationMode"] {
            guard let name = raw as? String, let parsed = CaptureConfirmationMode(rawValue: name) else {
                throw invalid("captureConfirmationMode")
            }
            mode = parsed
        }
        let panes = object["paneWidths"] as? [String: Any]
        let tags = (object["recentTags"] as? [String]) ?? []
        return AppSettings(
            storageFolderPath: path.trimmedNonEmpty ?? defaultStorageFolder.path,
            hasCompletedFirstRun: firstRun,
            theme: Theme(rawValue: themeName) ?? .system,
            captureConfirmationMode: mode,
            selectedTextShortcut: (object["selectedTextShortcut"] as? String)?.trimmedNonEmpty ?? Self.defaultShortcut,
            paneWidths: PaneWidths(
                sidebar: (panes?["sidebar"] as? Double) ?? PaneWidths.default.sidebar,
                library: (panes?["library"] as? Double) ?? PaneWidths.default.library),
            recentTags: Tags.limitedRecent(tags),
            updatedAt: updatedAt)
    }

    private func write(_ settings: AppSettings) throws {
        let object: [String: Any] = [
            "storageFolderPath": settings.storageFolderPath,
            "hasCompletedFirstRun": settings.hasCompletedFirstRun,
            "theme": settings.theme.rawValue,
            "captureConfirmationMode": settings.captureConfirmationMode.rawValue,
            "selectedTextShortcut": settings.selectedTextShortcut,
            "paneWidths": ["sidebar": settings.paneWidths.sidebar, "library": settings.paneWidths.library],
            "recentTags": settings.recentTags,
            "updatedAt": settings.updatedAt,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic) // temp file + rename; Foundation removes the temp file on failure
        } catch {
            throw PlopcutError("settings_unwritable", detail: error.localizedDescription)
        }
    }
}
