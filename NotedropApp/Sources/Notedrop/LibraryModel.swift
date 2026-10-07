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
    var selectedID: String? { didSet { editor.show(selectedDrop) } }

    var sidebarVisible = true
    /// The user's choice for the inspector beside the body. Narrow windows show it as an overlay instead (spec 2.2).
    var inspectorVisible = true
    var inspectorOverlayOpen = false
    /// Column widths restored at launch and saved only after a divider drag (spec L-15).
    private(set) var paneWidths = PaneWidths.default

    /// Library to show before settings exist: `NOTEDROP_STORAGE_FOLDER` overrides settings.json (dev and tests).
    private let storageRoot: @Sendable () throws -> URL

    private let settings: SettingsStore?
    private let trash: TrashMover
    /// Edits of the selected drop live here, not in the views, so toggling the inspector never loses a draft (E-05).
    private(set) var editor: DropEditor!
    /// One-line confirmation (trash, export) shown briefly; `alertMessage` is an error the user must dismiss.
    var notice: String?
    var alertMessage: String?
    /// The drop waiting for the "Move to Trash?" confirmation.
    var pendingDeleteID: String?

    init(
        storageRoot: @escaping @Sendable () throws -> URL = LibraryModel.defaultStorageRoot,
        settings: SettingsStore? = nil, trash: TrashMover = SystemTrashMover()
    ) {
        self.storageRoot = storageRoot
        self.settings = settings
        self.trash = trash
        paneWidths = (try? settings?.read().paneWidths) ?? .default
        let trashMover = trash
        editor = DropEditor(
            save: { id, update in try DropStore(root: try storageRoot(), trash: trashMover).update(id: id, update) },
            onSaved: { [weak self] in self?.apply($0) },
            onBackgroundFailure: { [weak self] code in self?.alertMessage = ErrorText.message(forCode: code) })
    }

    /// `NOTEDROP_SETTINGS_FILE` keeps dev runs and screenshots away from the user's real settings.json.
    static var defaultSettings: SettingsStore {
        if let override = ProcessInfo.processInfo.environment["NOTEDROP_SETTINGS_FILE"] {
            return SettingsStore(fileURL: URL(fileURLWithPath: override))
        }
        return SettingsStore()
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
        editor.show(selectedDrop)
    }

    /// A saved edit replaces the drop in the list; the selection stays on it.
    private func apply(_ saved: Drop) {
        guard let index = drops.firstIndex(where: { $0.id == saved.id }) else { return }
        // The selection stays on the edited drop even if it no longer matches the filter (spec E-06).
        drops[index] = saved
    }

    /// Moves the drop's folder to the Trash (spec 2.6). The drop stays in the list when the move fails.
    func delete(id: String) async -> Bool {
        let (root, trash) = (storageRoot, trash)
        let result: Result<Void, Error> = await Task.detached {
            Result { try DropStore(root: try root(), trash: trash).delete(id: id) }
        }.value
        switch result {
        case .success:
            editor.forget(id)
            drops.removeAll { $0.id == id }
            reselect()
            editor.show(selectedDrop)
            notice = L10n.t("trashSuccess")
            return true
        case .failure(let error):
            alertMessage = ErrorText.message(for: error)
            return false
        }
    }

    func exportMarkdown(of drop: Drop, to url: URL) -> Bool {
        do {
            try Data(MarkdownExport.render(drop).utf8).write(to: url, options: .atomic)
            notice = L10n.t("exportSuccess")
            return true
        } catch {
            alertMessage = ErrorText.message(for: NotedropError("export_failed", detail: error.localizedDescription))
            return false
        }
    }

    /// Pane widths are a convenience; a failed write keeps the in-memory value and retries on the next drag.
    func savePaneWidths(_ widths: PaneWidths) {
        paneWidths = widths
        _ = try? settings?.update(SettingsUpdate(paneWidths: widths))
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
