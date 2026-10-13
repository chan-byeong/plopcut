import Foundation
import PlopcutCore
import Observation

/// What the last folder action said, shown under the folder row and in the first-run modal.
enum StorageFolderNotice: Equatable {
    case cancelled, updated, confirmed
    case failed(String)
}

/// The storage folder row of Settings and the first-run modal (spec 4). Changing the folder only rewrites
/// `storageFolderPath`; existing drops stay where they are (S-17).
@MainActor
@Observable
final class StorageFolderModel {
    private(set) var path = ""
    private(set) var needsFirstRun = false
    private(set) var notice: StorageFolderNotice?
    /// Why the stored folder cannot hold drops right now, if it cannot.
    private(set) var problem: String?

    private let store: SettingsStore?
    private let picker: FolderPicker
    private let prepare: () async -> Bool
    /// `PLOPCUT_STORAGE_FOLDER` (dev and tests) wins over settings.json, so the screen must show and obey it.
    private let environmentOverride: String?
    private var isApplying = false
    private let onChanged: () -> Void

    /// `prepare` runs before the folder changes (pending edits are written to the old folder) and returns false
    /// when they could not be written, which stops the change; `onChanged` runs after.
    init(store: SettingsStore?, picker: FolderPicker, prepare: @escaping () async -> Bool = { true },
         onChanged: @escaping () -> Void = {},
         environmentOverride: String? = ProcessInfo.processInfo.environment["PLOPCUT_STORAGE_FOLDER"]) {
        self.store = store
        self.picker = picker
        self.environmentOverride = environmentOverride
        self.prepare = prepare
        self.onChanged = onChanged
        refresh()
    }

    func chooseFolder() async {
        guard let folder = picker.pickFolder(startingAt: URL(fileURLWithPath: path)) else { notice = .cancelled; return }
        await apply(SettingsUpdate(storageFolderPath: folder.path), folder: folder, success: .updated)
    }

    func useDefaultFolder() async {
        await apply(SettingsUpdate(hasCompletedFirstRun: true), folder: URL(fileURLWithPath: path), success: .confirmed)
    }

    func chooseFolderOnFirstRun() async {
        guard let folder = picker.pickFolder(startingAt: URL(fileURLWithPath: path)) else { notice = .cancelled; return }
        await apply(SettingsUpdate(storageFolderPath: folder.path, hasCompletedFirstRun: true), folder: folder, success: .updated)
    }

    private func apply(_ change: SettingsUpdate, folder: URL, success: StorageFolderNotice) async {
        guard let store, !isApplying else { return }
        if environmentOverride != nil, change.storageFolderPath != nil {
            notice = .failed("PLOPCUT_STORAGE_FOLDER overrides the storage folder setting.")
            return
        }
        isApplying = true
        defer { isApplying = false }
        do {
            try StorageFolderCheck.prepare(folder)
            guard await prepare() else {
                notice = .failed(L10n.t("saveFailed"))
                return
            }
            _ = try store.update(change)
            refresh()
            notice = success
            onChanged()
        } catch {
            notice = .failed(ErrorText.message(for: error))
        }
    }

    private func refresh() {
        guard let store else { return }
        do {
            let settings = try store.read()
            path = environmentOverride ?? settings.storageFolderPath
            needsFirstRun = !settings.hasCompletedFirstRun
            problem = StorageFolderCheck.problem(for: URL(fileURLWithPath: path)).map(ErrorText.message(for:))
        } catch {
            needsFirstRun = false
            problem = ErrorText.message(for: error)
        }
    }
}
