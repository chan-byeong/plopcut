import Foundation
import NotedropCore
import Observation

/// What the sidebar has selected. Exactly one row is selected at a time (spec 2.4).
enum SidebarSelection: Hashable {
    case all, text, image, tag(String), settings
}

@MainActor @Observable
final class LibraryModel {
    private(set) var drops: [Drop] = []
    private(set) var warnings: [ScanWarning] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    var collection: SidebarSelection = .all { didSet { if collection != oldValue { collectionChanged() } } }
    var search = "" { didSet { reselect() } }
    var app: String? { didSet { reselect() } }
    var dateRange: DateRange = .all { didSet { reselect() } }
    var selectedID: String?

    var sidebarVisible = true
    /// The user's choice for the inspector beside the body. Narrow windows show it as an overlay instead (spec 2.2).
    var inspectorVisible = true
    var inspectorOverlayOpen = false

    /// Library to show before settings exist: `NOTEDROP_STORAGE_FOLDER` overrides settings.json (dev and tests).
    private let storageRoot: @Sendable () throws -> URL

    init(storageRoot: @escaping @Sendable () throws -> URL = LibraryModel.defaultStorageRoot) {
        self.storageRoot = storageRoot
    }

    static let defaultStorageRoot: @Sendable () throws -> URL = {
        if let override = ProcessInfo.processInfo.environment["NOTEDROP_STORAGE_FOLDER"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: try SettingsStore().read().storageFolderPath, isDirectory: true)
    }

    // MARK: Derived state

    var filter: LibraryFilter {
        var type = TypeFilter.all
        var tag: String?
        switch collection {
        case .text: type = .text
        case .image: type = .image
        case .tag(let name): tag = name
        case .all, .settings: break
        }
        return LibraryFilter(search: search, type: type, tag: tag, app: app, dateRange: dateRange)
    }

    var filtered: [Drop] { filter.apply(drops) }
    var selectedDrop: Drop? { drops.first { $0.id == selectedID } }
    var hasRefiningFilters: Bool { app != nil || dateRange != .all }
    var allTags: [String] { Array(Set(drops.flatMap(\.tags))).sorted() }
    var allApps: [String] { Array(Set(drops.compactMap(\.source.appName))).sorted() }

    func count(for collection: SidebarSelection) -> Int {
        switch collection {
        case .all: drops.count
        case .text: drops.filter { $0.type == .text }.count
        case .image: drops.filter { $0.type == .image }.count
        case .tag(let name): drops.filter { $0.tags.contains(name) }.count
        case .settings: 0
        }
    }

    var title: String {
        switch collection {
        case .all, .settings: L10n.t("library")
        case .text: L10n.t("textDrops")
        case .image: L10n.t("imageDrops")
        case .tag(let name): name
        }
    }

    // MARK: Actions

    /// Re-scans the storage folder (initial load, refresh, and "saved elsewhere" signals).
    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let root = storageRoot
        let result: Result<DropScan, Error> = await Task.detached {
            Result { try DropStore(root: try root()).scan() }
        }.value
        switch result {
        case .success(let scan):
            drops = scan.drops
            warnings = scan.warnings
            loadError = nil
        case .failure(let error):
            drops = []
            warnings = []
            loadError = (error as? NotedropError)?.code ?? error.localizedDescription
        }
        reselect()
    }

    func clearFilters() {
        app = nil
        dateRange = .all
    }

    /// Selecting a type row clears the tag filter and vice versa because `collection` holds only one of them.
    private func collectionChanged() { reselect() }

    private func reselect() {
        selectedID = LibraryFilter.resolveSelection(selectedID, in: filtered)
    }
}
