import Foundation
import Testing
@testable import PlopcutCore

private func makeStore(_ root: URL, trash: TrashMover = SystemTrashMover()) -> DropStore {
    DropStore(root: root, clock: { sampleDate }, trash: trash)
}

private func json(_ url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

@Suite struct FixtureScanTests {
    @Test func scansFixturesInExpectedOrder() throws {
        let scan = try makeStore(Fixtures.copyStorage()).scan()
        let suffixes = scan.drops.map { $0.id.split(separator: "_", maxSplits: 3).last.map(String.init) ?? "" }
        #expect(suffixes == ["mixed", "legacy-minimal-text", "legacy-minimal-image", "image-drop", "drop", "example-app"])
        #expect(scan.warnings.map(\.code) == ["drop_scan_skipped"])
    }

    @Test func minimalTextDropGetsDefaults() throws {
        let drop = try #require(makeStore(Fixtures.copyStorage()).scan().drops.first { $0.id.hasSuffix("legacy-minimal-text") })
        #expect(drop.tags == ["research", "swift", "two words"])
        #expect(drop.source == DropSource())
        #expect(drop.note == nil)
        #expect(drop.text?.isEmpty == false)
    }

    @Test func minimalImageDropDefaultsToImagePng() throws {
        let drop = try #require(makeStore(Fixtures.copyStorage()).scan().drops.first { $0.id.hasSuffix("legacy-minimal-image") })
        #expect(drop.type == .image)
        #expect(drop.imagePath == "image.png")
        #expect(drop.imageURL != nil)
        #expect(drop.note == nil)
    }

    @Test func blankNoteIsNoNoteAndRealNoteIsKept() throws {
        let drops = try makeStore(Fixtures.copyStorage()).scan().drops
        #expect(drops.first { $0.id.hasSuffix("_drop") }?.note == nil)
        #expect(drops.first { $0.id.hasSuffix("image-drop") }?.note == "Whiteboard photo.")
        #expect(drops.first { $0.id.hasSuffix("example-app") }?.note?.hasSuffix("\n") == true)
    }

    @Test func mixedTypeDoesNotBreakScan() throws {
        let drop = try #require(makeStore(Fixtures.copyStorage()).scan().drops.first)
        #expect(drop.type == .mixed)
        #expect(drop.text == nil)
    }

    @Test func missingDropsFolderIsEmpty() throws {
        let scan = try makeStore(tempDir()).scan()
        #expect(scan.drops.isEmpty && scan.warnings.isEmpty)
    }

    @Test func unreadableNoteKeepsDropWithWarning() throws {
        let root = try Fixtures.copyStorage()
        let note = root.appendingPathComponent("drops/2026-01-01_090000_000000001_example-app/note.md")
        try FileManager.default.removeItem(at: note)
        try FileManager.default.createDirectory(at: note, withIntermediateDirectories: false) // a directory cannot be read as a file
        let scan = try makeStore(root).scan()
        #expect(scan.drops.contains { $0.id.hasSuffix("example-app") })
        #expect(scan.warnings.map(\.code).contains("drop_note_unreadable"))
    }

    @Test func missingContentKeepsDropWithWarning() throws {
        let root = try Fixtures.copyStorage()
        try FileManager.default.removeItem(
            at: root.appendingPathComponent("drops/2026-01-01_090000_000000001_example-app/content.md"))
        let scan = try makeStore(root).scan()
        #expect(scan.drops.contains { $0.id.hasSuffix("example-app") })
        #expect(scan.warnings.map(\.code).contains("drop_content_unreadable"))
    }

    @Test func missingImageKeepsDropWithWarning() throws {
        let root = try Fixtures.copyStorage()
        try FileManager.default.removeItem(
            at: root.appendingPathComponent("drops/2026-01-03_110000_000000003_image-drop/image.png"))
        let scan = try makeStore(root).scan()
        let drop = try #require(scan.drops.first { $0.id.hasSuffix("image-drop") })
        #expect(drop.imageURL == nil)
        #expect(scan.warnings.map(\.code).contains("drop_image_unreadable"))
    }

    @Test func unsafeImagePathIsNotFollowed() throws {
        let root = try Fixtures.copyStorage()
        let file = root.appendingPathComponent("drops/2026-01-03_110000_000000003_image-drop/drop.json")
        var meta = try json(file)
        meta["imagePath"] = "../../../etc/passwd"
        try JSONSerialization.data(withJSONObject: meta).write(to: file)
        let scan = try makeStore(root).scan()
        #expect(scan.drops.first { $0.id.hasSuffix("image-drop") }?.imageURL == nil)
        #expect(scan.warnings.map(\.code).contains("drop_image_unreadable"))
    }
}

@Suite struct SaveTests {
    @Test func savesTextDropInContractFormat() throws {
        let root = try tempDir()
        let store = makeStore(root)
        let drop = try store.saveText(
            "  hello\nworld \r\n", title: nil,
            source: DropSource(appName: "Cursor", windowTitle: nil, url: nil, filePath: nil),
            tags: ["#Swift", "swift"], note: nil)
        #expect(drop.id == "2026-10-02_063129_850365000_cursor")
        #expect(drop.title == "Cursor")
        let folder = root.appendingPathComponent("drops/\(drop.id)")
        #expect(try String(contentsOf: folder.appendingPathComponent("content.md"), encoding: .utf8) == "  hello\nworld ")
        #expect(try String(contentsOf: folder.appendingPathComponent("note.md"), encoding: .utf8) == "")
        let meta = try json(folder.appendingPathComponent("drop.json"))
        #expect(Set(meta.keys) == ["id", "type", "title", "text", "imagePath", "source", "note", "tags", "createdAt", "updatedAt",
                                  "pinnedAt"])
        #expect(meta["text"] is NSNull && meta["note"] is NSNull && meta["imagePath"] is NSNull)
        let source = try #require(meta["source"] as? [String: Any])
        #expect(Set(source.keys) == ["appName", "windowTitle", "url", "filePath"])
        #expect(source["url"] is NSNull)
        #expect(meta["tags"] as? [String] == ["swift"])
        #expect(meta["createdAt"] as? String == "2026-10-02T06:31:29.850365000Z")
        #expect(meta["createdAt"] as? String == meta["updatedAt"] as? String)
    }

    @Test func savedDropRoundTripsThroughScan() throws {
        let store = makeStore(try tempDir())
        let saved = try store.saveText("body", title: "한글 제목", source: DropSource(), tags: ["a"], note: "n")
        #expect(saved.id.hasSuffix("_drop"))
        let scanned = try store.scan().drops
        #expect(scanned == [saved])
    }

    @Test func collidingIdsGetNumericSuffix() throws {
        let store = makeStore(try tempDir())
        let first = try store.saveText("a", title: "same", source: DropSource(), tags: [], note: nil)
        let second = try store.saveText("b", title: "same", source: DropSource(), tags: [], note: nil)
        let third = try store.saveText("c", title: "same", source: DropSource(), tags: [], note: nil)
        #expect(second.id == first.id + "-2")
        #expect(third.id == first.id + "-3")
    }

    @Test func rejectsBlankText() throws {
        let store = makeStore(try tempDir())
        #expect(expectCode("empty_text") { try store.saveText(" \n\r\n", title: nil, source: DropSource(), tags: [], note: nil) })
    }

    @Test func savesImageDrop() throws {
        let root = try tempDir()
        let store = makeStore(root)
        let drop = try store.saveImage(pngBytes, title: nil, source: DropSource(), tags: [], note: "n")
        #expect(drop.title == "Image Drop")
        #expect(drop.type == .image && drop.imagePath == "image.png")
        let folder = root.appendingPathComponent("drops/\(drop.id)")
        #expect(try Data(contentsOf: folder.appendingPathComponent("image.png")) == pngBytes)
        let meta = try json(folder.appendingPathComponent("drop.json"))
        #expect(meta["imagePath"] as? String == "image.png")
        #expect(meta["text"] is NSNull)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("content.md").path))
    }

    @Test func rejectsEmptyAndNonPngImages() throws {
        let store = makeStore(try tempDir())
        #expect(expectCode("empty_image") { try store.saveImage(Data(), title: nil, source: DropSource(), tags: [], note: nil) })
        #expect(expectCode("invalid_image") { try store.saveImage(Data([1, 2, 3]), title: nil, source: DropSource(), tags: [], note: nil) })
    }

    @Test func unwritableRootFailsWithStorageUnwritable() throws {
        let root = try tempDir()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        #expect(expectCode("storage_unwritable") { try makeStore(root).saveText("a", title: nil, source: DropSource(), tags: [], note: nil) })
    }

    @Test func storageRootChangeIsRespected() throws {
        let a = try tempDir(), b = try tempDir()
        _ = try makeStore(a).saveText("a", title: nil, source: DropSource(), tags: [], note: nil)
        #expect(try makeStore(a).scan().drops.count == 1)
        #expect(try makeStore(b).scan().drops.isEmpty)
    }
}

@Suite struct UpdateTests {
    private func seeded() throws -> (DropStore, Drop, URL) {
        let root = try tempDir()
        let early = DropStore(root: root, clock: { sampleDate })
        let drop = try early.saveText("body", title: "T", source: DropSource(), tags: ["a"], note: "old")
        let later = DropStore(root: root, clock: { sampleDate.addingTimeInterval(60) })
        return (later, drop, root.appendingPathComponent("drops/\(drop.id)"))
    }

    @Test func updatesFieldsAndKeepsCreatedAt() throws {
        let (store, drop, _) = try seeded()
        let updated = try store.update(id: drop.id, DropUpdate(title: " New ", tags: ["#B", "b"], note: "new note", text: "new body\n"))
        #expect(updated.title == "New" && updated.tags == ["b"] && updated.note == "new note" && updated.text == "new body")
        #expect(updated.createdAt == drop.createdAt)
        #expect(updated.updatedAt > drop.updatedAt)
        #expect(try store.scan().drops == [updated])
    }

    @Test func blankTitleLeavesFilesUntouched() throws {
        let (store, drop, folder) = try seeded()
        let before = try Data(contentsOf: folder.appendingPathComponent("drop.json"))
        #expect(expectCode("invalid_title") { try store.update(id: drop.id, DropUpdate(title: "  ", note: "changed")) })
        #expect(try Data(contentsOf: folder.appendingPathComponent("drop.json")) == before)
        #expect(try String(contentsOf: folder.appendingPathComponent("note.md"), encoding: .utf8) == "old")
    }

    @Test func clearingNoteOverwritesFile() throws {
        let (store, drop, folder) = try seeded()
        let updated = try store.update(id: drop.id, DropUpdate(note: ""))
        #expect(updated.note == nil)
        #expect(try String(contentsOf: folder.appendingPathComponent("note.md"), encoding: .utf8) == "")
    }

    @Test func imageDropKeepsImageOnUpdate() throws {
        let root = try tempDir()
        let store = makeStore(root)
        let drop = try store.saveImage(pngBytes, title: "Pic", source: DropSource(), tags: [], note: nil)
        let updated = try store.update(id: drop.id, DropUpdate(title: "Pic2", tags: ["x"], note: "n", text: "ignored"))
        #expect(updated.title == "Pic2" && updated.text == nil && updated.imageURL != nil)
        #expect(try Data(contentsOf: root.appendingPathComponent("drops/\(drop.id)/image.png")) == pngBytes)
    }

    @Test func rejectsBadAndUnknownIds() throws {
        let store = makeStore(try tempDir())
        for bad in ["", ".", "a/b", "..", "x\\y"] {
            #expect(expectCode("invalid_drop_id") { try store.update(id: bad, DropUpdate(title: "x")) })
        }
        #expect(expectCode("drop_not_found") { try store.update(id: "nope", DropUpdate(title: "x")) })
    }
}

@Suite struct DeleteTests {
    struct RecordingTrash: TrashMover {
        func trash(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
    }
    struct NoopTrash: TrashMover {
        func trash(_ url: URL) throws {}
    }
    struct ThrowingTrash: TrashMover {
        struct Boom: Error {}
        func trash(_ url: URL) throws { throw Boom() }
    }

    @Test func deleteRemovesDropFromScan() throws {
        let store = makeStore(try tempDir(), trash: RecordingTrash())
        let drop = try store.saveText("a", title: nil, source: DropSource(), tags: [], note: nil)
        try store.delete(id: drop.id)
        #expect(try store.scan().drops.isEmpty)
    }

    @Test func failedMoveLeavesDropAndReportsDeleteFailed() throws {
        for trash in [NoopTrash() as TrashMover, ThrowingTrash()] {
            let store = makeStore(try tempDir(), trash: trash)
            let drop = try store.saveText("a", title: nil, source: DropSource(), tags: [], note: nil)
            #expect(expectCode("delete_failed") { try store.delete(id: drop.id) })
            #expect(try store.scan().drops.count == 1)
        }
    }

    @Test func deleteValidatesId() throws {
        let store = makeStore(try tempDir(), trash: RecordingTrash())
        #expect(expectCode("invalid_drop_id") { try store.delete(id: "../x") })
        #expect(expectCode("drop_not_found") { try store.delete(id: "missing") })
    }
}
