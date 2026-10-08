import Foundation
import NotedropCore
import Testing
@testable import Notedrop

@MainActor
private final class FakePicker: FolderPicker {
    var result: URL?
    private(set) var startedAt: [URL?] = []
    func pickFolder(startingAt: URL?) -> URL? {
        startedAt.append(startingAt)
        return result
    }
}

@MainActor
@Suite struct StorageFolderModelTests {
    private struct Env {
        let dir: URL
        let store: SettingsStore
        let defaultFolder: URL
    }

    private func makeEnv() throws -> Env {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("storage-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaultFolder = dir.appendingPathComponent("Notedrop", isDirectory: true)
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json"), defaultStorageFolder: defaultFolder)
        return Env(dir: dir, store: store, defaultFolder: defaultFolder)
    }

    private func makeFolder(_ env: Env, _ name: String) throws -> URL {
        let url = env.dir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func model(_ env: Env, picker: FakePicker = FakePicker(), prepare: @escaping () async -> Bool = { true },
                       onChanged: @escaping () -> Void = {}, environmentOverride: String? = nil) -> StorageFolderModel {
        StorageFolderModel(
            store: env.store, picker: picker, prepare: prepare, onChanged: onChanged,
            environmentOverride: environmentOverride)
    }

    @Test func aFailedFlushOfPendingEditsKeepsTheOldFolder() async throws {
        let env = try makeEnv()
        let picker = FakePicker()
        picker.result = try makeFolder(env, "Other")
        var changes = 0
        let m = model(env, picker: picker, prepare: { false }, onChanged: { changes += 1 })
        await m.chooseFolder()
        #expect(try env.store.read().storageFolderPath == env.defaultFolder.path)
        #expect(changes == 0)
        guard case .failed? = m.notice else { Issue.record("expected a failure notice"); return }
    }

    @Test func theEnvironmentOverrideIsShownAndBlocksFolderChanges() async throws {
        let env = try makeEnv()
        let override = try makeFolder(env, "FromEnv").path
        let picker = FakePicker()
        picker.result = try makeFolder(env, "Other")
        let m = model(env, picker: picker, environmentOverride: override)
        #expect(m.path == override)
        await m.chooseFolder()
        #expect(try env.store.read().storageFolderPath == env.defaultFolder.path)
        guard case .failed? = m.notice else { Issue.record("expected a failure notice"); return }
    }

    @Test func freshSettingsShowTheDefaultFolderAndAskForFirstRun() throws {
        let env = try makeEnv()
        let m = model(env)
        #expect(m.path == env.defaultFolder.path)
        #expect(m.needsFirstRun)
    }

    @Test func completedFirstRunDoesNotAsk() throws {
        let env = try makeEnv()
        _ = try env.store.update(SettingsUpdate(hasCompletedFirstRun: true))
        #expect(!model(env).needsFirstRun)
    }

    // S-17: after the change, everything that resolves the storage root sees the new folder.
    @Test func choosingAFolderSavesItKeepsOtherFieldsAndReloads() async throws {
        let env = try makeEnv()
        _ = try env.store.update(SettingsUpdate(hasCompletedFirstRun: true, theme: .dark))
        let target = try makeFolder(env, "Other")
        let picker = FakePicker()
        picker.result = target
        var changes = 0
        let m = model(env, picker: picker, onChanged: { changes += 1 })
        await m.chooseFolder()
        let stored = try env.store.read()
        #expect(stored.storageFolderPath == target.path)
        #expect(stored.theme == .dark)
        #expect(stored.hasCompletedFirstRun)
        #expect(m.path == target.path)
        #expect(m.notice == .updated)
        #expect(changes == 1)
        #expect(picker.startedAt.first??.path == env.defaultFolder.path)
    }

    @Test func cancellingTheChoiceKeepsTheFolderAndSaysSo() async throws {
        let env = try makeEnv()
        _ = try env.store.update(SettingsUpdate(hasCompletedFirstRun: true))
        var changes = 0
        let m = model(env, onChanged: { changes += 1 })
        await m.chooseFolder()
        #expect(m.notice == .cancelled)
        #expect(m.path == env.defaultFolder.path)
        #expect(try env.store.read().storageFolderPath == env.defaultFolder.path)
        #expect(changes == 0)
    }

    @Test func aFolderThatCannotHoldDropsIsRefusedAndNothingChanges() async throws {
        let env = try makeEnv()
        _ = try env.store.update(SettingsUpdate(hasCompletedFirstRun: true))
        let file = env.dir.appendingPathComponent("plain.txt")
        try Data("x".utf8).write(to: file)
        let picker = FakePicker()
        picker.result = file
        var changes = 0
        let m = model(env, picker: picker, onChanged: { changes += 1 })
        await m.chooseFolder()
        #expect(m.notice == .failed(L10n.t("storageFailure")))
        #expect(m.path == env.defaultFolder.path)
        #expect(try env.store.read().storageFolderPath == env.defaultFolder.path)
        #expect(changes == 0)
    }

    @Test func pendingEditsAreFlushedBeforeTheFolderChanges() async throws {
        let env = try makeEnv()
        _ = try env.store.update(SettingsUpdate(hasCompletedFirstRun: true))
        let picker = FakePicker()
        picker.result = try makeFolder(env, "Other")
        var log: [String] = []
        let m = model(env, picker: picker, prepare: { log.append("prepare"); return true }, onChanged: { log.append("changed") })
        await m.chooseFolder()
        #expect(log == ["prepare", "changed"])
    }

    @Test func usingTheDefaultFolderCreatesItAndCompletesFirstRun() async throws {
        let env = try makeEnv()
        var changes = 0
        let m = model(env, onChanged: { changes += 1 })
        await m.useDefaultFolder()
        #expect(FileManager.default.fileExists(atPath: env.defaultFolder.path))
        #expect(try env.store.read().hasCompletedFirstRun)
        #expect(!m.needsFirstRun)
        #expect(m.notice == .confirmed)
        #expect(changes == 1)
    }

    @Test func theModalStaysWhenTheDefaultFolderCannotBeUsed() async throws {
        let env = try makeEnv()
        try Data("x".utf8).write(to: env.defaultFolder)
        let m = model(env)
        await m.useDefaultFolder()
        #expect(m.needsFirstRun)
        #expect(m.notice == .failed(L10n.t("storageFailure")))
        #expect(try !env.store.read().hasCompletedFirstRun)
    }

    @Test func cancellingTheFirstRunChoiceKeepsTheModal() async throws {
        let env = try makeEnv()
        let m = model(env)
        await m.chooseFolderOnFirstRun()
        #expect(m.needsFirstRun)
        #expect(m.notice == .cancelled)
        #expect(try !env.store.read().hasCompletedFirstRun)
    }

    @Test func choosingAFolderOnFirstRunSavesItAndCompletesFirstRun() async throws {
        let env = try makeEnv()
        let target = try makeFolder(env, "Chosen")
        let picker = FakePicker()
        picker.result = target
        var changes = 0
        let m = model(env, picker: picker, onChanged: { changes += 1 })
        await m.chooseFolderOnFirstRun()
        let stored = try env.store.read()
        #expect(stored.storageFolderPath == target.path)
        #expect(stored.hasCompletedFirstRun)
        #expect(!m.needsFirstRun)
        #expect(m.notice == .updated)
        #expect(changes == 1)
    }

    @Test func aStoredFolderThatIsNotUsableShowsTheReason() throws {
        let env = try makeEnv()
        let file = env.dir.appendingPathComponent("plain.txt")
        try Data("x".utf8).write(to: file)
        _ = try env.store.update(SettingsUpdate(storageFolderPath: file.path, hasCompletedFirstRun: true))
        #expect(model(env).problem == L10n.t("storageFailure"))
    }

    @Test func aUsableStoredFolderShowsNoProblem() throws {
        let env = try makeEnv()
        _ = try env.store.update(SettingsUpdate(hasCompletedFirstRun: true))
        #expect(model(env).problem == nil)
    }
}

@Suite struct StorageRootResolutionTests {
    private func makeStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("root-resolution-\(UUID().uuidString)")
        return SettingsStore(fileURL: dir.appendingPathComponent("settings.json"), defaultStorageFolder: dir.appendingPathComponent("Default"))
    }

    // S-17 at the app layer: scan and save follow the configured folder, and move with it.
    @Test func scanAndSaveUseTheFolderThatSettingsPointsAt() throws {
        let store = makeStore()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("root-pair-\(UUID().uuidString)")
        let first = base.appendingPathComponent("first"), second = base.appendingPathComponent("second")
        _ = try store.update(SettingsUpdate(storageFolderPath: first.path))
        let a = try DropStore(root: try LibraryModel.resolveStorageRoot(settings: store, environment: [:]))
            .saveText("one", title: "one", source: DropSource(), tags: [], note: nil)
        _ = try store.update(SettingsUpdate(storageFolderPath: second.path))
        let secondRoot = try LibraryModel.resolveStorageRoot(settings: store, environment: [:])
        #expect(secondRoot.path == second.path)
        #expect(try DropStore(root: secondRoot).scan().drops.isEmpty)
        _ = try DropStore(root: secondRoot).saveText("two", title: "two", source: DropSource(), tags: [], note: nil)
        #expect(try DropStore(root: secondRoot).scan().drops.count == 1)
        #expect(try DropStore(root: first).scan().drops.map(\.id) == [a.id])
    }

    @Test func theDevEnvironmentOverrideWinsOverSettings() throws {
        let store = makeStore()
        let root = try LibraryModel.resolveStorageRoot(settings: store, environment: ["NOTEDROP_STORAGE_FOLDER": "/tmp/dev-root"])
        #expect(root.path == "/tmp/dev-root")
    }
}
