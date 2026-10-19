import Foundation
import Testing
@testable import PlopcutCore

// R-01, R-02: the `format` and `codeLanguage` keys of drop.json (spec 1.2, PLO-101).

private let later = sampleDate.addingTimeInterval(3600)

private func store(_ root: URL, at date: Date = sampleDate) -> DropStore {
    DropStore(root: root, clock: { date })
}

private func meta(_ root: URL, _ id: String) throws -> [String: Any] {
    let url = root.appendingPathComponent("drops/\(id)/drop.json")
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func copyFormatFixtures() throws -> URL {
    let dest = try tempDir()
    try FileManager.default.copyItem(
        at: Fixtures.root.appendingPathComponent("storage-format/drops"), to: dest.appendingPathComponent("drops"))
    return dest
}

@Suite struct DropFormatStorageTests {
    @Test func newDropsWriteBothKeysAsNull() throws {
        let root = try tempDir()
        let drop = try store(root).saveText("hello", title: nil, source: DropSource(), tags: [], note: nil)
        let json = try meta(root, drop.id)
        #expect(json.keys.contains("format") && json["format"] is NSNull)
        #expect(json.keys.contains("codeLanguage") && json["codeLanguage"] is NSNull)
        #expect(drop.format == nil && drop.codeLanguage == nil)
    }

    @Test func choosingCodeWritesBothKeysAndReadsBack() throws {
        let root = try tempDir()
        let saved = try store(root).saveText("print(1)", title: nil, source: DropSource(), tags: [], note: nil)
        let updated = try store(root, at: later).update(id: saved.id, DropUpdate(format: .set(.code, codeLanguage: "python")))
        #expect(updated.format == .code && updated.codeLanguage == "python")
        let json = try meta(root, saved.id)
        #expect(json["format"] as? String == "code")
        #expect(json["codeLanguage"] as? String == "python")
        let scanned = try #require(store(root).scan().drops.first)
        #expect(scanned.format == .code && scanned.codeLanguage == "python")
    }

    @Test func nonCodeFormatDropsTheLanguage() throws {
        let root = try tempDir()
        let saved = try store(root).saveText("# Hi", title: nil, source: DropSource(), tags: [], note: nil)
        let updated = try store(root).update(id: saved.id, DropUpdate(format: .set(.markdown, codeLanguage: "swift")))
        #expect(updated.format == .markdown && updated.codeLanguage == nil)
        #expect(try meta(root, saved.id)["codeLanguage"] is NSNull)
    }

    @Test func automaticClearsBothKeys() throws {
        let root = try tempDir()
        let saved = try store(root).saveText("x", title: nil, source: DropSource(), tags: [], note: nil)
        _ = try store(root).update(id: saved.id, DropUpdate(format: .set(.code, codeLanguage: "swift")))
        let cleared = try store(root).update(id: saved.id, DropUpdate(format: .automatic))
        #expect(cleared.format == nil && cleared.codeLanguage == nil)
        let json = try meta(root, saved.id)
        #expect(json["format"] is NSNull && json["codeLanguage"] is NSNull)
    }

    @Test func formatChangeKeepsUpdatedAtAndContent() throws {
        let root = try tempDir()
        let saved = try store(root).saveText("body\n", title: nil, source: DropSource(), tags: [], note: nil)
        let content = root.appendingPathComponent("drops/\(saved.id)/content.md")
        let before = try Data(contentsOf: content)
        let changed = try store(root, at: later).update(id: saved.id, DropUpdate(format: .set(.plain, codeLanguage: nil)))
        #expect(changed.updatedAt == saved.updatedAt)
        #expect(try meta(root, saved.id)["updatedAt"] as? String == saved.updatedAt)
        #expect(try Data(contentsOf: content) == before)
        let cleared = try store(root, at: later).update(id: saved.id, DropUpdate(format: .automatic))
        #expect(cleared.updatedAt == saved.updatedAt)
    }

    @Test func contentEditsStillMoveUpdatedAtAndKeepTheFormat() throws {
        let root = try tempDir()
        let saved = try store(root).saveText("body", title: nil, source: DropSource(), tags: [], note: nil)
        _ = try store(root).update(id: saved.id, DropUpdate(format: .set(.markdown, codeLanguage: nil)))
        let edited = try store(root, at: later).update(id: saved.id, DropUpdate(note: "n"))
        #expect(edited.updatedAt == Timestamp.format(later))
        #expect(edited.format == .markdown)
    }

    @Test func legacyDropsWithoutTheKeysReadAsAutomatic() throws {
        for drop in try store(Fixtures.copyStorage()).scan().drops {
            #expect(drop.format == nil && drop.codeLanguage == nil, "\(drop.id)")
        }
    }

    @Test func formatFixturesReadAsDocumented() throws {
        let scan = try store(copyFormatFixtures()).scan()
        #expect(scan.warnings.isEmpty)
        let byName = Dictionary(uniqueKeysWithValues: scan.drops.map { ($0.id.split(separator: "_").last.map(String.init) ?? "", $0) })
        #expect(byName["code-choice"]?.format == .code)
        #expect(byName["code-choice"]?.codeLanguage == "python")
        #expect(byName["markdown-choice"]?.format == .markdown)
        #expect(byName["markdown-choice"]?.codeLanguage == nil)
        #expect(byName["unknown-format"]?.format == nil)
        #expect(byName["unknown-format"]?.codeLanguage == nil)
    }

    @Test func rewritingAnUnknownFormatStoresNull() throws {
        let root = try copyFormatFixtures()
        let id = "2026-02-01_090000_000000001_unknown-format"
        _ = try store(root).update(id: id, DropUpdate(title: "Renamed"))
        let json = try meta(root, id)
        #expect(json["format"] is NSNull && json["codeLanguage"] is NSNull)
    }

    @Test func formatChangeOnMissingDropFails() throws {
        let root = try Fixtures.copyStorage()
        #expect(expectCode("drop_not_found") { try store(root).update(id: "2030-01-01_000000_000000000_nope", DropUpdate(format: .automatic)) })
    }
}
