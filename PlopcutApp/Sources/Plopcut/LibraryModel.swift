import AppKit
import Foundation
import PlopcutCore
import Observation
import UniformTypeIdentifiers

/// What the sidebar has selected. Exactly one row is selected at a time (spec 2.4).
enum SidebarSelection: Hashable {
    case all, text, image, pinned, tag(String), settings
}

/// A row of the filter popover's source list (spec 2.5, PLO-103).
struct SourceCount: Equatable {
    let key: SourceKey
    let count: Int
}

/// The filter popover's source list, websites before apps.
struct SourceGroups: Equatable {
    var websites: [SourceCount] = []
    var apps: [SourceCount] = []
}

@MainActor @Observable
final class LibraryModel {
    private(set) var drops: [Drop] = []
    /// Derived from `drops` and the filter inputs when they change, not on every view update (5,000-drop library, STA-80).
    private(set) var filtered: [Drop] = []
    /// The Pinned section first, then the date groups (spec 1.6).
    private(set) var sections: [(section: ListSection, drops: [Drop])] = []
    private(set) var allTags: [String] = []
    private var typeCounts: (text: Int, image: Int) = (0, 0)
    private var pinnedCount = 0
    private var tagCounts: [String: Int] = [:]
    private var searchIndex = SearchIndex()
    private(set) var warnings: [ScanWarning] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    /// The sidebar row. Switching away from unsaved content edits waits for "Discard changes?" (spec 2.6, E-10).
    var collection: SidebarSelection {
        get { currentCollection }
        set {
            guard newValue != currentCollection else { return }
            editor.requestLeave { [weak self] in self?.currentCollection = newValue }
            if currentCollection != newValue { echo(\.shownCollection, newValue) }
        }
    }
    /// What the sidebar shows as selected. Equal to `collection` except for one turn after a held switch.
    var sidebarSelection: SidebarSelection {
        get { shownCollection ?? collection }
        set { collection = newValue }
    }
    private var shownCollection: SidebarSelection?
    private var currentCollection: SidebarSelection = .all { didSet { if currentCollection != oldValue { collectionChanged() } } }
    var search = "" { didSet { reselect() } }
    /// The selected sources; empty means no source filter (spec 1.6, PLO-103).
    var sources: Set<SourceKey> = [] { didSet { if sources != oldValue { reselect() } } }
    var dateRange: DateRange = .all { didSet { reselect() } }
    /// The selected drop. Picking another one away from unsaved content edits waits for "Discard changes?" (E-10).
    var selectedID: String? {
        get { currentSelection }
        set {
            guard newValue != currentSelection else { return }
            editor.requestLeave { [weak self] in self?.currentSelection = newValue }
            if currentSelection != newValue { echo(\.shownSelection, newValue) }
        }
    }
    /// What the list shows as selected. Equal to `selectedID` except for one turn after a held move.
    var listSelection: String? {
        get { shownSelection ?? currentSelection }
        set { selectedID = newValue }
    }
    private var shownSelection: String??

    /// A held move leaves the clicked row highlighted, because the bound value never changed. Showing the clicked value
    /// for one turn and then the kept one gives the list a real change to follow back (E-10).
    private func echo<Value>(_ shown: ReferenceWritableKeyPath<LibraryModel, Value?>, _ value: Value) {
        self[keyPath: shown] = value
        Task { @MainActor [weak self] in self?[keyPath: shown] = nil }
    }
    private var currentSelection: String? { didSet { editor.show(selectedDrop) } }

    var sidebarVisible = true
    /// The user's choice for the inspector beside the body. Narrow windows show it as an overlay instead (spec 2.2).
    var inspectorVisible = true
    var inspectorOverlayOpen = false
    /// Column widths restored at launch and saved only after a divider drag (spec L-15).
    private(set) var paneWidths = PaneWidths.default

    /// Library to show before settings exist: `PLOPCUT_STORAGE_FOLDER` overrides settings.json (dev and tests).
    private let storageRoot: @Sendable () throws -> URL

    private let settings: SettingsStore?
    private let trash: TrashMover
    /// Edits of the selected drop live here, not in the views, so toggling the inspector never loses a draft (E-05).
    private(set) var editor: DropEditor!
    /// One-line confirmation (trash, export) shown briefly; `alertMessage` is an error the user must dismiss.
    var notice: String?
    var alertMessage: String? { didSet { if alertMessage == nil { alertRecovery = nil } } }
    /// The button offered with `alertMessage` when the user can fix the cause (STA-78), e.g. open System Settings.
    var alertRecovery: ErrorRecovery?
    private let openURL: (URL) -> Void
    /// The drop waiting for the "Move to Trash?" confirmation.
    var pendingDeleteID: String?
    /// A capture failure waiting for the main window; shown once (spec 3.3, checklist P-13).
    let pendingCapture = PendingCaptureError()

    init(
        storageRoot: @escaping @Sendable () throws -> URL = LibraryModel.defaultStorageRoot,
        settings: SettingsStore? = nil, trash: TrashMover = SystemTrashMover(),
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.openURL = openURL
        self.storageRoot = storageRoot
        self.settings = settings
        self.trash = trash
        paneWidths = (try? settings?.read().paneWidths) ?? .default
        let trashMover = trash
        editor = DropEditor(
            save: { id, update in try DropStore(root: try storageRoot(), trash: trashMover).update(id: id, update) },
            onSaved: { [weak self] in self?.apply($0) },
            onBackgroundFailure: { [weak self] code in self?.showAlert(forCode: code, logged: false) })
    }

    /// `PLOPCUT_SETTINGS_FILE` keeps dev runs and screenshots away from the user's real settings.json.
    static var defaultSettings: SettingsStore {
        settingsStore(environment: ProcessInfo.processInfo.environment)
    }

    nonisolated static func settingsStore(environment: [String: String]) -> SettingsStore {
        if let override = environment["PLOPCUT_SETTINGS_FILE"] {
            return SettingsStore(fileURL: URL(fileURLWithPath: override))
        }
        return SettingsStore()
    }

    /// `PLOPCUT_STORAGE_FOLDER` wins over settings.json (dev and tests); otherwise the folder is read on every use,
    /// so a folder changed in Settings is followed by the next scan and save (S-17).
    nonisolated static func resolveStorageRoot(settings: SettingsStore, environment: [String: String]) throws -> URL {
        if let override = environment["PLOPCUT_STORAGE_FOLDER"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: try settings.read().storageFolderPath, isDirectory: true)
    }

    static let defaultStorageRoot: @Sendable () throws -> URL = {
        let environment = ProcessInfo.processInfo.environment
        return try resolveStorageRoot(settings: settingsStore(environment: environment), environment: environment)
    }

    // MARK: Derived state

    var filter: LibraryFilter {
        var type = TypeFilter.all
        var tag: String?
        switch collection {
        case .text: type = .text
        case .image: type = .image
        case .tag(let name): tag = name
        case .all, .pinned, .settings: break
        }
        var filter = LibraryFilter(search: search, type: type, tag: tag, sources: sources, dateRange: dateRange)
        filter.pinnedOnly = collection == .pinned
        return filter
    }

    /// The Pinned collection lists drops by pin time without the "Pinned" header (spec 2.5).
    var showsSectionHeaders: Bool { collection != .pinned }

    var selectedDrop: Drop? { drops.first { $0.id == selectedID } }
    var hasRefiningFilters: Bool { !sources.isEmpty || dateRange != .all }

    /// Whether "Show Drops from This Source" can act on the drop.
    static func hasSource(_ drop: Drop) -> Bool { SourceKey(drop.source) != nil }

    /// The popover's sources with counts under every condition but the source filter (Collection, search, period).
    /// A selected source stays listed even at 0 so it can be unchecked. Each group sorts by count, then name.
    /// A non-blank `query` keeps the sources whose name contains it, ignoring case.
    func sourceGroups(matching query: String) -> SourceGroups {
        var unfiltered = filter
        unfiltered.sources = []
        var counts: [SourceKey: Int] = Dictionary(uniqueKeysWithValues: sources.map { ($0, 0) })
        for drop in unfiltered.apply(drops, index: searchIndex) {
            if let key = SourceKey(drop.source) { counts[key, default: 0] += 1 }
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows: [SourceCount] = counts
            .map { SourceCount(key: $0.key, count: $0.value) }
            .filter { needle.isEmpty || $0.key.name.localizedStandardContains(needle) }
            .sorted(by: Self.listsBefore)
        var groups = SourceGroups()
        for row in rows {
            if case .website = row.key { groups.websites.append(row) } else { groups.apps.append(row) }
        }
        return groups
    }

    private static func listsBefore(_ a: SourceCount, _ b: SourceCount) -> Bool {
        if a.count != b.count { return a.count > b.count }
        return a.key.name.localizedStandardCompare(b.key.name) == .orderedAscending
    }

    func count(for collection: SidebarSelection) -> Int {
        switch collection {
        case .all: drops.count
        case .text: typeCounts.text
        case .image: typeCounts.image
        case .pinned: pinnedCount
        case .tag(let name): tagCounts[name] ?? 0
        case .settings: 0
        }
    }

    var title: String {
        switch collection {
        case .all, .settings: L10n.t("library")
        case .text: L10n.t("textDrops")
        case .image: L10n.t("imageDrops")
        case .pinned: L10n.t("pinned")
        case .tag(let name): name
        }
    }

    // MARK: Actions

    /// Re-scans the storage folder (initial load, refresh, and saves from the Save Popup).
    /// With `selecting`, that drop becomes the selection afterwards, clearing any filter that hides it (checklist L-10).
    func reload(selecting id: String? = nil) async {
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
            dropsChanged(rebuildIndex: true)
        case .failure(let error):
            drops = []
            warnings = []
            dropsChanged(rebuildIndex: true)
            AppLog.shared.log(error: error)
            loadError = (error as? PlopcutError)?.code ?? error.localizedDescription
        }
        reselect()
        // An open content editor keeps its drop selected; the new drop is in the list for later (spec 2.6).
        if let id, !editor.isEditingBody, drops.contains(where: { $0.id == id }) {
            if !filtered.contains(where: { $0.id == id }) {
                search = ""
                clearFilters()
                collection = .all
            }
            selectedID = id
        }
        editor.show(selectedDrop)
    }

    /// Shows the stored capture failure, once, as `{pendingFailed}: {message}`.
    func presentPendingCaptureError() {
        guard let error = pendingCapture.take() else { return }
        showAlert(forCode: error.code, prefix: "\(L10n.t("pendingFailed")): ")
    }

    /// Shows an error with its recovery button when there is one.
    /// `logged: false` when the failure was already logged where it happened (a background autosave).
    func showAlert(forCode code: String, prefix: String = "", logged: Bool = true) {
        if logged { AppLog.shared.log(.error(code: code)) }
        alertMessage = prefix + ErrorText.message(forCode: code)
        alertRecovery = ErrorRecovery.forCode(code)
    }

    /// Runs the button next to the alert, then the alert is dismissed by the system.
    func performRecovery() {
        guard let recovery = alertRecovery else { return }
        switch recovery {
        case .openAccessibilitySettings:
            if let url = PermissionsModel.accessibilitySettingsURL { openURL(url) }
        case .openPlopcutSettings:
            collection = .settings
        }
        alertMessage = nil
    }

    /// A saved edit replaces the drop in the list; the selection stays on it.
    private func apply(_ saved: Drop) {
        guard let index = drops.firstIndex(where: { $0.id == saved.id }) else { return }
        // The selection stays on the edited drop even if it no longer matches the filter (spec E-06).
        drops[index] = saved
        searchIndex.insert(saved)
        dropsChanged(rebuildIndex: false)
    }

    /// Stores or clears the drop's format choice (spec 2.6, R-08). Not a content edit, so `updatedAt` stays.
    /// On failure the drop keeps its old format and the error is shown.
    func setFormat(_ change: FormatUpdate, for id: String) async {
        let (root, trash) = (storageRoot, trash)
        let result: Result<Drop, Error> = await Task.detached {
            Result { try DropStore(root: try root(), trash: trash).update(id: id, DropUpdate(format: change)) }
        }.value
        switch result {
        case .success(let saved): apply(saved)
        case .failure(let error): showAlert(forCode: (error as? PlopcutError)?.code ?? "")
        }
    }

    // MARK: Content editing (spec 2.6 "본문 편집")

    /// Whether Edit (button, context menu, Cmd+E) can start on the selected drop: a text drop, no editor open yet.
    var canEditBody: Bool {
        collection != .settings && !editor.isEditingBody && DropEditor.canEditBody(selectedDrop)
    }

    /// Opens the content editor on the selected drop. Returns false for an image drop or nothing selected.
    @discardableResult
    func beginBodyEdit() -> Bool {
        guard collection != .settings, let drop = selectedDrop else { return false }
        return editor.beginBodyEdit(drop)
    }

    /// Edit from the list's context menu: selects that drop first (which may ask to discard another edit).
    func beginBodyEdit(id: String) {
        selectedID = id
        if selectedID == id { beginBodyEdit() }
    }

    /// Opens a link from a rendered body in the default browser. Only web and mail links open (spec 2.6, R-07).
    func openLink(_ url: URL) {
        guard Self.isOpenableLink(url) else { return }
        openURL(url)
    }

    nonisolated static func isOpenableLink(_ url: URL) -> Bool {
        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }

    /// Pins or unpins the drop (spec 2.5, 2.6). The selection stays on it while it is still listed; unpinning in the
    /// Pinned collection removes it from the list, so the selection then follows spec 1.6.
    func togglePin(id: String) async {
        guard let drop = drops.first(where: { $0.id == id }) else { return }
        let (root, pinned) = (storageRoot, !drop.isPinned)
        let result: Result<Drop, Error> = await Task.detached {
            Result { try DropStore(root: try root()).update(id: id, DropUpdate(pinned: pinned)) }
        }.value
        switch result {
        case .success(let saved):
            apply(saved)
            reselect()
        case .failure(let error):
            showAlert(forCode: (error as? PlopcutError)?.code ?? "")
        }
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
            searchIndex.remove(id: id)
            dropsChanged(rebuildIndex: false)
            reselect()
            editor.show(selectedDrop)
            notice = L10n.t("trashSuccess")
            return true
        case .failure(let error):
            showAlert(forCode: (error as? PlopcutError)?.code ?? "")
            return false
        }
    }

    /// Pending edits are saved first and the drop is read again after the panel closes, so the file holds what
    /// the user sees. Cancelling the save panel writes nothing (spec 7). Shared by the detail button and the list menu.
    func exportWithPanel(id: String) async {
        guard await editor.drain() else { alertMessage = L10n.t("saveFailed"); return }
        guard let drop = drops.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = MarkdownExport.fileName(for: drop)
        if let markdown = UTType(filenameExtension: "md") { panel.allowedContentTypes = [markdown] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard await editor.drain() else { alertMessage = L10n.t("saveFailed"); return }
        guard let latest = drops.first(where: { $0.id == id }) else { return }
        _ = exportMarkdown(of: latest, to: url)
    }

    func exportMarkdown(of drop: Drop, to url: URL) -> Bool {
        do {
            try Data(MarkdownExport.render(drop).utf8).write(to: url, options: .atomic)
            notice = L10n.t("exportSuccess")
            return true
        } catch {
            showAlert(forCode: "export_failed")
            return false
        }
    }

    /// Pane widths are a convenience; a failed write keeps the in-memory value and retries on the next drag.
    func savePaneWidths(_ widths: PaneWidths) {
        paneWidths = widths
        _ = try? settings?.update(SettingsUpdate(paneWidths: widths))
    }

    /// Clears sources and period; the sidebar selection and the search stay (spec 2.5).
    func clearFilters() {
        sources = []
        dateRange = .all
    }

    /// The chip of one source removes only that source.
    func removeSource(_ key: SourceKey) { sources.remove(key) }

    /// "Show Drops from This Source": the Library Collection filtered to the drop's source alone; the period and the
    /// search stay. A drop without source changes nothing (spec 2.5).
    func showDropsFromSource(of drop: Drop) {
        guard let key = SourceKey(drop.source) else { return }
        editor.requestLeave { [weak self] in
            self?.currentCollection = .all
            self?.sources = [key]
        }
    }

    /// Selecting a type row clears the tag filter and vice versa because `collection` holds only one of them.
    private func collectionChanged() { reselect() }

    /// Recomputes everything derived from `drops`: counts, the tag list, the search index, and the filtered list.
    private func dropsChanged(rebuildIndex: Bool) {
        if rebuildIndex { searchIndex = SearchIndex(drops) }
        var tags: [String: Int] = [:]
        var text = 0, image = 0, pinned = 0
        for drop in drops {
            if drop.type == .text { text += 1 } else if drop.type == .image { image += 1 }
            if drop.isPinned { pinned += 1 }
            for tag in drop.tags { tags[tag, default: 0] += 1 }
        }
        typeCounts = (text, image)
        pinnedCount = pinned
        tagCounts = tags
        allTags = tags.keys.sorted()
        refilter()
    }

    private func refilter() {
        filtered = filter.apply(drops, index: searchIndex)
        sections = ListSection.make(filtered)
    }

    private func reselect() {
        refilter()
        // While the content editor is open its drop stays selected, even if the list no longer shows it (spec 2.6).
        if editor.isEditingBody { return }
        // "The first item" is the first row shown, so a pinned drop comes before the date groups (spec 1.6).
        currentSelection = LibraryFilter.resolveSelection(currentSelection, in: sections.flatMap(\.drops))
    }
}
