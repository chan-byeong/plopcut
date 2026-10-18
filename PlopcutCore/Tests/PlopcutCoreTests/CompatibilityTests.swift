import Foundation
import Testing
@testable import PlopcutCore

// Saved-drop-folder compatibility (STA-77): checklist S items checked against the fixtures,
// always on a temporary copy. See docs/swift-migration/fixtures/README.md for the expectations.

private var fm: FileManager { .default }

private func store(_ root: URL, at date: Date = sampleDate) -> DropStore {
    DropStore(root: root, clock: { date })
}

private func folder(_ root: URL, _ id: String) -> URL {
    root.appendingPathComponent("drops/\(id)", isDirectory: true)
}

private func object(_ url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func fixtureText(_ id: String, _ file: String) throws -> String {
    try String(contentsOf: Fixtures.root.appendingPathComponent("storage/drops/\(id)/\(file)"), encoding: .utf8)
}

private let contractKeys: Set<String> = [
    "id", "type", "title", "text", "imagePath", "source", "note", "tags", "createdAt", "updatedAt",
    "pinnedAt",
]

private enum ID {
    static let mixed = "2026-01-06_140000_000000006_mixed"
    static let broken = "2026-01-05_130000_000000005_broken-json"
    static let minimalText = "2026-01-04_120000_000000000_legacy-minimal-text"
    static let minimalImage = "2026-01-04_120000_000000000_legacy-minimal-image"
    static let image = "2026-01-03_110000_000000003_image-drop"
    static let korean = "2026-01-02_100000_000000002_drop"
    static let text = "2026-01-01_090000_000000001_example-app"
}

@Suite struct FixtureExpectationTests {
    // Fixture README table, row by row (S-02, S-03, S-04, S-12, S-20, D-02).
    @Test func everyFixtureScansAsTheReadmeExpects() throws {
        let root = try Fixtures.copyStorage()
        let scan = try store(root).scan()
        #expect(scan.drops.map(\.id) == [ID.mixed, ID.minimalText, ID.minimalImage, ID.image, ID.korean, ID.text])

        let byID = Dictionary(uniqueKeysWithValues: scan.drops.map { ($0.id, $0) })
        let mixed = try #require(byID[ID.mixed])
        #expect(mixed.type == .mixed && mixed.title == "Mixed type from another tool")
        #expect(mixed.text == nil && mixed.imageURL == nil && mixed.note == nil && mixed.tags.isEmpty)
        #expect(mixed.source == DropSource(appName: "Other Tool"))

        let minimalText = try #require(byID[ID.minimalText])
        #expect(minimalText.type == .text && minimalText.title == "Legacy minimal")
        #expect(minimalText.text == (try fixtureText(ID.minimalText, "content.md")))
        #expect(minimalText.tags == ["research", "swift", "two words"])
        #expect(minimalText.source == DropSource() && minimalText.note == nil && minimalText.imagePath == nil)

        let minimalImage = try #require(byID[ID.minimalImage])
        #expect(minimalImage.type == .image && minimalImage.imagePath == "image.png")
        #expect(minimalImage.imageURL?.resolvingSymlinksInPath().path
            == folder(root, ID.minimalImage).appendingPathComponent("image.png").resolvingSymlinksInPath().path)
        #expect(minimalImage.note == nil && minimalImage.tags.isEmpty && minimalImage.text == nil)

        let image = try #require(byID[ID.image])
        #expect(image.note == "Whiteboard photo." && image.imageURL != nil)
        #expect(image.source == DropSource(appName: "Preview", windowTitle: "diagram.png"))

        let korean = try #require(byID[ID.korean])
        #expect(korean.title == "한글 제목 문서" && korean.tags == ["한글", "메모"] && korean.note == nil)
        #expect(korean.source.url == "https://example.com/wiki/한글")
        #expect(korean.text == (try fixtureText(ID.korean, "content.md")))
        #expect(korean.createdAt == "2026-01-02T10:00:00.000000002Z" && korean.updatedAt == "2026-01-02T10:30:00.000000002Z")

        let text = try #require(byID[ID.text])
        #expect(text.text == (try fixtureText(ID.text, "content.md")))
        #expect(text.text?.contains("\n\nSecond paragraph.") == true)
        #expect(text.note == "A note with **markdown**.\n")
        #expect(text.tags == ["research", "swift"])

        // Exactly one warning, for the broken folder; the stray file is ignored silently.
        #expect(scan.warnings.count == 1)
        #expect(scan.warnings.first?.code == "drop_scan_skipped")
        #expect(scan.warnings.first?.message.contains("broken-json") == true)
    }

    // S-02: only id, type, title, createdAt and updatedAt are required.
    @Test func aMissingRequiredKeySkipsOnlyThatDrop() throws {
        for key in ["id", "type", "title", "createdAt", "updatedAt"] {
            let root = try Fixtures.copyStorage()
            let file = folder(root, ID.text).appendingPathComponent("drop.json")
            var meta = try object(file)
            meta.removeValue(forKey: key)
            try JSONSerialization.data(withJSONObject: meta).write(to: file)
            let scan = try store(root).scan()
            #expect(!scan.drops.contains { $0.id == ID.text }, "missing \(key)")
            #expect(scan.drops.count == 5, "missing \(key)")
            #expect(scan.warnings.map(\.code) == ["drop_scan_skipped", "drop_scan_skipped"], "missing \(key)")
        }
    }

    // S-02: explicit nulls for optional keys read like missing keys.
    @Test func nullOptionalKeysReadLikeMissingKeys() throws {
        let root = try Fixtures.copyStorage()
        let file = folder(root, ID.text).appendingPathComponent("drop.json")
        var meta = try object(file)
        meta["source"] = NSNull(); meta["tags"] = NSNull()
        try JSONSerialization.data(withJSONObject: meta).write(to: file)
        let drop = try #require(store(root).scan().drops.first { $0.id == ID.text })
        #expect(drop.source == DropSource() && drop.tags.isEmpty)
    }

    // S-12: whitespace-only note.md counts as no note.
    @Test func whitespaceOnlyNoteIsNoNote() throws {
        let root = try Fixtures.copyStorage()
        try Data(" \n\t\n".utf8).write(to: folder(root, ID.text).appendingPathComponent("note.md"))
        #expect(try store(root).scan().drops.first { $0.id == ID.text }?.note == nil)
    }

    // Spec 1.1: non-folder entries such as .DS_Store are ignored without a warning.
    @Test func filesNextToDropFoldersAreIgnored() throws {
        let root = try Fixtures.copyStorage()
        try Data([0, 1, 2]).write(to: root.appendingPathComponent("drops/.DS_Store"))
        let scan = try store(root).scan()
        #expect(scan.drops.count == 6 && scan.warnings.count == 1)
    }

    // Legacy follows symlinks when it checks `is_dir`, so a linked drop folder is listed.
    @Test func aSymlinkedDropFolderIsListed() throws {
        let root = try Fixtures.copyStorage()
        let elsewhere = try tempDir().appendingPathComponent(ID.text)
        try fm.moveItem(at: folder(root, ID.text), to: elsewhere)
        try fm.createSymbolicLink(at: folder(root, ID.text), withDestinationURL: elsewhere)
        let scan = try store(root).scan()
        #expect(scan.drops.contains { $0.id == ID.text })
        #expect(scan.drops.count == 6)
    }

    // S-19: a `drops` entry that cannot be listed is an error, not an empty Library.
    @Test func aDropsEntryThatIsNotAFolderIsUnreadable() throws {
        let root = try tempDir()
        try Data("x".utf8).write(to: root.appendingPathComponent("drops"))
        #expect(expectCode("storage_unreadable") { try store(root).scan() })
    }

    @Test func anUnlistableDropsFolderIsUnreadable() throws {
        try #require(geteuid() != 0, "permission checks do not apply to root")
        let root = try Fixtures.copyStorage()
        let drops = root.appendingPathComponent("drops")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: drops.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: drops.path) }
        #expect(expectCode("storage_unreadable") { try store(root).scan() })
    }
}

@Suite struct FixtureRewriteTests {
    // S-01: rewriting a minimal legacy drop.json normalizes it to the full contract.
    @Test func editingAMinimalTextDropWritesTheFullContract() throws {
        let root = try Fixtures.copyStorage()
        _ = try store(root).update(id: ID.minimalText, DropUpdate(title: "Edited", tags: ["x"], note: "n"))
        let file = folder(root, ID.minimalText).appendingPathComponent("drop.json")
        let meta = try object(file)
        #expect(Set(meta.keys) == contractKeys)
        #expect(meta["text"] is NSNull && meta["note"] is NSNull && meta["imagePath"] is NSNull)
        let source = try #require(meta["source"] as? [String: Any])
        #expect(Set(source.keys) == ["appName", "windowTitle", "url", "filePath"])
        #expect(source.values.allSatisfy { $0 is NSNull })
        #expect(meta["createdAt"] as? String == "2026-01-04T12:00:00.000000000Z")
        #expect(meta["tags"] as? [String] == ["x"])
    }

    // S-01, D-04: an image drop always records `imagePath`, even when the legacy file omitted it.
    @Test func editingAMinimalImageDropRecordsImagePng() throws {
        let root = try Fixtures.copyStorage()
        _ = try store(root).update(id: ID.minimalImage, DropUpdate(title: "Edited", note: ""))
        let meta = try object(folder(root, ID.minimalImage).appendingPathComponent("drop.json"))
        #expect(Set(meta.keys) == contractKeys)
        #expect(meta["imagePath"] as? String == "image.png")
        #expect(meta["text"] is NSNull && meta["note"] is NSNull)
    }

    // S-01: the written file has the same key set as a saved fixture, two-space indentation,
    // unescaped slashes and non-ASCII text, and no `imageDataUrl`.
    @Test func savedFilesMatchTheFixtureShape() throws {
        let root = try Fixtures.copyStorage()
        let saved = try store(root).saveText(
            "본문", title: "한글", source: DropSource(appName: "A", url: "https://example.com/a"), tags: [], note: nil)
        let file = folder(root, saved.id).appendingPathComponent("drop.json")
        let fixture = try object(folder(root, ID.text).appendingPathComponent("drop.json"))
        #expect(Set(try object(file).keys) == Set(fixture.keys))
        let raw = try String(contentsOf: file, encoding: .utf8)
        #expect(!raw.contains("imageDataUrl"))
        #expect(raw.contains("https://example.com/a") && raw.contains("한글"))
        let indents = raw.split(separator: "\n").dropFirst().dropLast().map { $0.prefix { $0 == " " }.count }
        #expect(!indents.isEmpty && indents.allSatisfy { $0 > 0 && $0 % 2 == 0 })
    }

    // S-13, S-14, D-02: every fixture drop can be edited and still reads back with its createdAt.
    @Test func everyFixtureDropSurvivesAnEditAndRescan() throws {
        let root = try Fixtures.copyStorage()
        let before = try store(root).scan().drops
        let later = store(root, at: sampleDate)
        for drop in before {
            let updated = try later.update(id: drop.id, DropUpdate(title: drop.title + " edited", tags: drop.tags + ["edited"], note: "note"))
            #expect(updated.createdAt == drop.createdAt && updated.type == drop.type)
            #expect(updated.updatedAt == Timestamp.format(sampleDate))
            #expect(updated.text == drop.text && updated.imagePath == drop.imagePath)
        }
        let after = try store(root).scan()
        #expect(after.drops.map(\.id) == before.map(\.id))
        #expect(after.drops.allSatisfy { $0.title.hasSuffix(" edited") && $0.note == "note" && $0.tags.last == "edited" })
        #expect(after.warnings.map(\.code) == ["drop_scan_skipped"])
        // The copy changed; the fixture itself did not.
        #expect(try fixtureText(ID.text, "note.md") == "A note with **markdown**.\n")
    }

    // S-04, S-05: a new drop saved next to legacy drops sorts by time with them.
    @Test func newDropsSortAmongLegacyDrops() throws {
        let root = try Fixtures.copyStorage()
        // Date holds about microsecond precision, so pick a time that is not nanoseconds away.
        let between = try #require(Timestamp.parse("2026-01-03T11:00:00.000001Z"))
        let saved = try store(root, at: between).saveText("x", title: "between", source: DropSource(), tags: [], note: nil)
        let ids = try store(root).scan().drops.map(\.id)
        #expect(ids == [ID.mixed, ID.minimalText, ID.minimalImage, saved.id, ID.image, ID.korean, ID.text])
    }

    // S-11: an image drop also gets an (empty) note.md.
    @Test func newImageDropsAlwaysGetANoteFile() throws {
        let root = try Fixtures.copyStorage()
        let saved = try store(root).saveImage(pngBytes, title: nil, source: DropSource(), tags: [], note: nil)
        let note = folder(root, saved.id).appendingPathComponent("note.md")
        #expect(try String(contentsOf: note, encoding: .utf8) == "")
    }
}

@Suite struct TimestampCompatibilityTests {
    // S-05: microsecond-apart times still format to nine digits and sort as strings.
    @Test func closeTimesSortAsStrings() {
        let base = Date(timeIntervalSince1970: 1_790_922_689)
        let dates = (0..<50).map { base.addingTimeInterval(Double($0 * 7 % 50) * 0.000_001 + Double($0 % 3)) }
        let stamps = dates.map(Timestamp.format)
        #expect(stamps.allSatisfy { $0.count == "2026-10-02T06:31:29.000000000Z".count && $0.hasSuffix("Z") })
        let byString = zip(dates, stamps).sorted { $0.1 < $1.1 }.map(\.0)
        #expect(byString == dates.sorted())
    }

    // S-05: the format is what legacy wrote, so new and legacy stamps compare correctly.
    @Test func nowIsNineDigitsAndAfterLegacyStamps() {
        let now = Timestamp.format(Date())
        let fraction = now.split(separator: ".").last?.dropLast() ?? ""
        #expect(fraction.count == 9 && fraction.allSatisfy(\.isNumber))
        #expect(now > "2026-01-06T14:00:00.000000006Z")
    }
}

@Suite struct NamingCompatibilityTests {
    // S-15: a blank ID is invalid, like an empty one.
    @Test func blankIdsAreInvalid() throws {
        let root = try Fixtures.copyStorage()
        for blank in [" ", "\t", " \n "] {
            #expect(!Naming.isValidDropID(blank))
            #expect(expectCode("invalid_drop_id") { try store(root).update(id: blank, DropUpdate(title: "x")) })
        }
    }

    // S-07: legacy lowercases before keeping ASCII letters and digits, so a character whose
    // lowercase is ASCII (Kelvin sign) still counts.
    @Test func slugLowercasesBeforeFiltering() {
        #expect(Naming.slug("\u{212A}ilo") == "kilo")
        #expect(Naming.slug("Ab\u{212A}") == "abk")
    }
}

/// Manual check on a copy of a real legacy folder. Set PLOPCUT_COMPAT_FOLDER to a storage folder
/// (the one that contains `drops/`). The folder is copied first; the original is never written.
@Suite struct RealFolderCopyTests {
    static let source = ProcessInfo.processInfo.environment["PLOPCUT_COMPAT_FOLDER"]

    @Test(.enabled(if: source != nil)) func aCopyOfARealFolderScansEditsAndRescans() throws {
        let original = URL(fileURLWithPath: try #require(Self.source), isDirectory: true)
        let copy = try tempDir().appendingPathComponent("storage")
        try fm.copyItem(at: original, to: copy)
        defer { try? fm.removeItem(at: copy.deletingLastPathComponent()) }

        let first = try store(copy).scan()
        let folders = try fm.contentsOfDirectory(at: copy.appendingPathComponent("drops"), includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        #expect(first.drops.count + first.warnings.filter { $0.code == "drop_scan_skipped" }.count == folders.count)
        print("real folder copy: \(first.drops.count) drops, warnings: \(first.warnings.map(\.code))")

        for drop in first.drops {
            _ = try store(copy).update(id: drop.id, DropUpdate(title: drop.title, tags: drop.tags, note: drop.note ?? ""))
            let meta = try object(folder(copy, drop.id).appendingPathComponent("drop.json"))
            #expect(Set(meta.keys) == contractKeys, "\(drop.id)")
        }
        let second = try store(copy).scan()
        #expect(second.drops.map(\.id) == first.drops.map(\.id))
        for (a, b) in zip(first.drops, second.drops) {
            #expect(a.title == b.title && a.tags == b.tags && a.note == b.note && a.text == b.text, "\(a.id)")
            #expect(a.createdAt == b.createdAt && a.source == b.source && a.imagePath == b.imagePath, "\(a.id)")
        }
    }
}
