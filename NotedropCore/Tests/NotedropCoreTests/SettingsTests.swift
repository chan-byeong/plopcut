import Foundation
import Testing
@testable import NotedropCore

private let defaultFolder = URL(fileURLWithPath: "/Users/test/Documents/Notedrop")

private func store(_ file: URL, clockOffset: TimeInterval = 0) -> SettingsStore {
    SettingsStore(fileURL: file, defaultStorageFolder: defaultFolder, clock: { sampleDate.addingTimeInterval(clockOffset) })
}

private func tempFile(copying fixture: String? = nil) throws -> URL {
    let dir = try tempDir()
    let file = dir.appendingPathComponent("settings.json")
    if let fixture { try FileManager.default.copyItem(at: Fixtures.root.appendingPathComponent(fixture), to: file) }
    return file
}

private func write(_ object: [String: Any], to file: URL) throws {
    try JSONSerialization.data(withJSONObject: object).write(to: file)
}

private var required: [String: Any] { [
    "storageFolderPath": "/x", "hasCompletedFirstRun": true, "theme": "dark", "updatedAt": "2026-01-01T00:00:00.000000000Z",
] }

@Suite struct SettingsReadTests {
    @Test func missingFileCreatesDefaults() throws {
        let file = try tempFile()
        let settings = try store(file).read()
        #expect(settings.storageFolderPath == defaultFolder.path)
        #expect(settings.theme == .system && settings.captureConfirmationMode == .modal)
        #expect(settings.selectedTextShortcut == "Shift+Cmd+C")
        #expect(settings.paneWidths == PaneWidths(sidebar: 220, library: 330))
        #expect(settings.recentTags.isEmpty && !settings.hasCompletedFirstRun)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func readsFullFixture() throws {
        let s = try store(tempFile(copying: "settings.json")).read()
        #expect(s.theme == .dark && s.paneWidths == PaneWidths(sidebar: 215, library: 373))
        #expect(s.recentTags == ["research", "swift"] && s.hasCompletedFirstRun)
    }

    @Test func legacyFixtureFillsDefaultsAndFixesTheme() throws {
        let s = try store(tempFile(copying: "settings-legacy.json")).read()
        #expect(s.theme == .system && s.captureConfirmationMode == .modal)
        #expect(s.selectedTextShortcut == "Shift+Cmd+C" && s.paneWidths == PaneWidths(sidebar: 220, library: 330))
        #expect(s.recentTags.isEmpty && !s.hasCompletedFirstRun)
    }

    @Test func clampFixtureNormalizes() throws {
        let s = try store(tempFile(copying: "settings-clamp.json")).read()
        #expect(s.storageFolderPath == defaultFolder.path)
        #expect(s.selectedTextShortcut == "Shift+Cmd+C")
        #expect(s.paneWidths == PaneWidths(sidebar: 180, library: 560))
        #expect(s.recentTags == ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"])
        #expect(s.captureConfirmationMode == .instant)
    }

    @Test func brokenAndIncompleteFilesAreInvalid() throws {
        let file = try tempFile()
        try Data("{ nope".utf8).write(to: file)
        #expect(expectCode("settings_invalid") { try store(file).read() })
        for key in required.keys {
            var partial = required
            partial.removeValue(forKey: key)
            try write(partial, to: file)
            #expect(expectCode("settings_invalid") { try store(file).read() }, "missing \(key)")
        }
        var badMode = required
        badMode["captureConfirmationMode"] = "sometimes"
        try write(badMode, to: file)
        #expect(expectCode("settings_invalid") { try store(file).read() })
    }

    @Test func unreadableFile() throws {
        let file = try tempFile()
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        #expect(expectCode("settings_unreadable") { try store(file).read() })
    }
}

@Suite struct SettingsUpdateTests {
    @Test func partialUpdateKeepsOtherFieldsAndBumpsTimestamp() throws {
        let file = try tempFile(copying: "settings.json")
        let updated = try store(file, clockOffset: 5).update(SettingsUpdate(hasCompletedFirstRun: false, theme: .light))
        #expect(updated.theme == .light && !updated.hasCompletedFirstRun)
        #expect(updated.paneWidths == PaneWidths(sidebar: 215, library: 373))
        #expect(updated.updatedAt == Timestamp.format(sampleDate.addingTimeInterval(5)))
        #expect(try store(file).read() == updated)
    }

    @Test func clampsPaneWidthsAndNormalizesRecentTags() throws {
        let file = try tempFile(copying: "settings.json")
        let updated = try store(file).update(SettingsUpdate(
            paneWidths: PaneWidths(sidebar: 10, library: 10_000), recentTags: ["#A", "a"] + (0..<20).map { "t\($0)" }))
        #expect(updated.paneWidths == PaneWidths(sidebar: 180, library: 560))
        #expect(updated.recentTags.count == 12 && updated.recentTags.first == "a")
    }

    @Test func rejectsBlankStorageFolderWithoutWriting() throws {
        let file = try tempFile(copying: "settings.json")
        let before = try Data(contentsOf: file)
        #expect(expectCode("invalid_storage_folder") { try store(file).update(SettingsUpdate(storageFolderPath: "  ")) })
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func rejectsUnparseableShortcutWithoutWriting() throws {
        let file = try tempFile(copying: "settings.json")
        let before = try Data(contentsOf: file)
        #expect(expectCode("invalid_selected_text_shortcut") { try store(file).update(SettingsUpdate(selectedTextShortcut: "Shift+Banana")) })
        #expect(try Data(contentsOf: file) == before)
        let ok = try store(file).update(SettingsUpdate(selectedTextShortcut: "Ctrl+Option+K"))
        #expect(ok.selectedTextShortcut == "Ctrl+Option+K")
    }

    @Test func writtenFileUsesContractKeysAndLeavesNoTempFiles() throws {
        let file = try tempFile()
        _ = try store(file).update(SettingsUpdate(captureConfirmationMode: .instant))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(Set(object.keys) == ["storageFolderPath", "hasCompletedFirstRun", "theme", "captureConfirmationMode",
                                     "selectedTextShortcut", "paneWidths", "recentTags", "updatedAt"])
        #expect(object["captureConfirmationMode"] as? String == "instant")
        let siblings = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        #expect(siblings == ["settings.json"])
    }

    // C-01
    @Test func theSettingsFileLivesInApplicationSupportWhateverTheStorageFolderIs() throws {
        #expect(SettingsStore.defaultFileURL.path.hasSuffix("/Library/Application Support/Notedrop/settings.json"))
        let file = try tempFile()
        let elsewhere = try tempDir()
        let s = store(file)
        _ = try s.update(SettingsUpdate(storageFolderPath: elsewhere.path))
        #expect(try s.read().storageFolderPath == elsewhere.path)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    // C-07: a failed write keeps the previous file and leaves no temp file behind.
    @Test func aFailedWriteKeepsTheOldFileAndLeavesNoTempFile() throws {
        try #require(geteuid() != 0, "permission checks do not apply to root")
        let file = try tempFile(copying: "settings.json")
        let dir = file.deletingLastPathComponent()
        let before = try Data(contentsOf: file)
        let s = store(file)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(expectCode("settings_unwritable") { try s.update(SettingsUpdate(theme: .light)) })
        #expect(try Data(contentsOf: file) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["settings.json"])
    }

    @Test func concurrentUpdatesAreSerialized() throws {
        let file = try tempFile(copying: "settings.json")
        let s = store(file)
        DispatchQueue.concurrentPerform(iterations: 20) { i in
            _ = try? s.update(SettingsUpdate(recentTags: ["t\(i)"]))
        }
        let final = try s.read()
        #expect(final.recentTags.count == 1)
        #expect(final.theme == .dark)
    }
}

@Suite struct ShortcutTests {
    @Test func parsesModifiersAndKeys() throws {
        let a = try Shortcut.parse("Shift+Cmd+C")
        #expect(a.modifiers == [.shift, .command] && a.key == "C")
        let b = try Shortcut.parse("control+alt+f5")
        #expect(b.modifiers == [.control, .option] && b.key == "F5")
        #expect(try Shortcut.parse("Command+Option+Space").key == "Space")
        #expect(try Shortcut.parse(" Cmd + 1 ").key == "1")
    }

    @Test func rejectsInvalid() {
        for bad in ["", "  ", "Shift+", "+C", "Shift+Banana", "Hyper+C", "Cmd+C+D", "Cmd", "Shift+Cmd"] {
            #expect(expectCode("invalid_selected_text_shortcut") { try Shortcut.parse(bad) }, "\(bad)")
        }
    }
}
