import Foundation
import Testing
@testable import PlopcutCore

private var fm: FileManager { .default }

private struct Layout {
    let home: URL
    var legacySupport: URL { home.appendingPathComponent("Library/Application Support/Notedrop", isDirectory: true) }
    var support: URL { home.appendingPathComponent("Library/Application Support/plopcut", isDirectory: true) }
    var legacyDocs: URL { home.appendingPathComponent("Documents/Notedrop", isDirectory: true) }
    var docs: URL { home.appendingPathComponent("Documents/plopcut", isDirectory: true) }
    var legacyLogs: URL { home.appendingPathComponent("Library/Logs/Notedrop", isDirectory: true) }
    var logs: URL { home.appendingPathComponent("Library/Logs/plopcut", isDirectory: true) }

    init() throws { home = try tempDir() }

    func settingsFile(in support: URL) -> URL { support.appendingPathComponent("settings.json") }

    func makeDrop(in storage: URL, id: String = "2026-01-01_000000_000000001_a") throws {
        try fm.createDirectory(at: storage.appendingPathComponent("drops/\(id)"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: storage.appendingPathComponent("drops/\(id)/drop.json"))
    }

    func writeSettings(in support: URL, storageFolder: URL) throws {
        let store = SettingsStore(fileURL: settingsFile(in: support), defaultStorageFolder: storageFolder)
        _ = try store.update(SettingsUpdate(storageFolderPath: storageFolder.path, hasCompletedFirstRun: true))
    }

    func storagePath() throws -> String {
        try SettingsStore(fileURL: settingsFile(in: support), defaultStorageFolder: docs).read().storageFolderPath
    }

    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
}

@Suite struct LegacyMigrationTests {
    @Test func movesSettingsAndTheDefaultDropFolder() throws {
        let l = try Layout()
        try l.makeDrop(in: l.legacyDocs)
        try l.writeSettings(in: l.legacySupport, storageFolder: l.legacyDocs)

        let errors = LegacyMigration(home: l.home).run()

        #expect(errors.isEmpty)
        #expect(!l.exists(l.legacyDocs) && !l.exists(l.legacySupport))
        #expect(l.exists(l.docs.appendingPathComponent("drops/2026-01-01_000000_000000001_a/drop.json")))
        #expect(try l.storagePath() == l.docs.path)
    }

    @Test func movesTheDropFolderWhenThereIsNoSettingsFile() throws {
        let l = try Layout()
        try l.makeDrop(in: l.legacyDocs)

        let errors = LegacyMigration(home: l.home).run()

        #expect(errors.isEmpty)
        #expect(l.exists(l.docs.appendingPathComponent("drops")) && !l.exists(l.legacyDocs))
        #expect(!l.exists(l.settingsFile(in: l.support)))
    }

    @Test func keepsACustomStorageFolder() throws {
        let l = try Layout()
        let custom = try tempDir()
        try l.makeDrop(in: custom)
        try fm.createDirectory(at: l.legacyDocs, withIntermediateDirectories: true)
        try l.writeSettings(in: l.legacySupport, storageFolder: custom)

        let errors = LegacyMigration(home: l.home).run()

        #expect(errors.isEmpty)
        #expect(l.exists(l.legacyDocs) && !l.exists(l.docs))
        #expect(l.exists(custom.appendingPathComponent("drops")))
        #expect(try l.storagePath() == custom.path)
    }

    @Test func neverOverwritesExistingPlopcutFolders() throws {
        let l = try Layout()
        try l.makeDrop(in: l.legacyDocs)
        try l.makeDrop(in: l.docs, id: "2026-02-02_000000_000000002_b")
        try l.writeSettings(in: l.legacySupport, storageFolder: l.legacyDocs)
        try l.writeSettings(in: l.support, storageFolder: l.docs)

        let errors = LegacyMigration(home: l.home).run()

        #expect(errors.isEmpty)
        #expect(l.exists(l.legacyDocs) && l.exists(l.legacySupport))
        #expect(l.exists(l.docs.appendingPathComponent("drops/2026-02-02_000000_000000002_b")))
        #expect(!l.exists(l.docs.appendingPathComponent("drops/2026-01-01_000000_000000001_a")))
        #expect(try l.storagePath() == l.docs.path)
    }

    @Test func doesNothingWithoutLegacyFolders() throws {
        let l = try Layout()

        let errors = LegacyMigration(home: l.home).run()

        #expect(errors.isEmpty)
        #expect(!l.exists(l.docs) && !l.exists(l.support) && !l.exists(l.logs))
    }

    @Test func movesTheLogFolderAndRenamesItsFiles() throws {
        let l = try Layout()
        try fm.createDirectory(at: l.legacyLogs, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: l.legacyLogs.appendingPathComponent("notedrop.log"))
        try Data("b".utf8).write(to: l.legacyLogs.appendingPathComponent("notedrop.log.1"))

        let errors = LegacyMigration(home: l.home).run()

        #expect(errors.isEmpty)
        #expect(!l.exists(l.legacyLogs))
        #expect(try String(contentsOf: l.logs.appendingPathComponent("plopcut.log"), encoding: .utf8) == "a")
        #expect(try String(contentsOf: l.logs.appendingPathComponent("plopcut.log.1"), encoding: .utf8) == "b")
    }

    @Test func rollsTheDropFolderBackWhenSettingsCannotBeSaved() throws {
        let l = try Layout()
        try l.makeDrop(in: l.legacyDocs)
        try l.writeSettings(in: l.legacySupport, storageFolder: l.legacyDocs)
        // The new settings folder already exists, so it is not moved, and it cannot be written to.
        try fm.createDirectory(at: l.support, withIntermediateDirectories: true)
        try fm.copyItem(at: l.settingsFile(in: l.legacySupport), to: l.settingsFile(in: l.support))
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: l.support.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: l.support.path) }

        let errors = LegacyMigration(home: l.home).run()

        #expect(errors.map(\.code) == ["settings_unwritable"])
        #expect(l.exists(l.legacyDocs.appendingPathComponent("drops")) && !l.exists(l.docs))
    }

    @Test func aBrokenSettingsFileLeavesTheDropFolderAlone() throws {
        let l = try Layout()
        try l.makeDrop(in: l.legacyDocs)
        try fm.createDirectory(at: l.legacySupport, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: l.settingsFile(in: l.legacySupport))

        let errors = LegacyMigration(home: l.home).run()

        #expect(errors.map(\.code) == ["settings_invalid"])
        #expect(l.exists(l.legacyDocs) && !l.exists(l.docs))
        #expect(l.exists(l.settingsFile(in: l.support)))
    }
}
