import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

// R-07, R-08: the format menu and link opening through LibraryModel (spec 2.6, PLO-101).
@MainActor
@Suite struct DropFormatModelTests {
    private static let textID = "2026-01-01_090000_000000001_example-app"

    private func copyStorage() throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/swift-migration/fixtures/storage")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }

    private func loaded(_ root: URL, openURL: @escaping (URL) -> Void = { _ in }) async -> LibraryModel {
        let model = LibraryModel(storageRoot: { root }, openURL: openURL)
        await model.reload()
        return model
    }

    @Test func choosingAFormatPersistsAcrossRelaunchAndKeepsTheSelection() async throws {
        let root = try copyStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = await loaded(root)
        model.selectedID = Self.textID
        let before = try #require(model.selectedDrop)

        await model.setFormat(.set(.code, codeLanguage: "swift"), for: Self.textID)

        #expect(model.selectedID == Self.textID)
        #expect(model.selectedDrop?.format == .code)
        #expect(model.selectedDrop?.codeLanguage == "swift")
        #expect(model.selectedDrop?.updatedAt == before.updatedAt)
        #expect(model.selectedDrop?.text == before.text)
        #expect(model.alertMessage == nil)

        let relaunched = await loaded(root)
        let reread = try #require(relaunched.drops.first { $0.id == Self.textID })
        #expect(reread.format == .code && reread.codeLanguage == "swift")
    }

    @Test func choosingAutomaticClearsTheChoice() async throws {
        let root = try copyStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = await loaded(root)
        await model.setFormat(.set(.markdown, codeLanguage: nil), for: Self.textID)
        await model.setFormat(.automatic, for: Self.textID)
        #expect(model.drops.first { $0.id == Self.textID }?.format == nil)
        let relaunched = await loaded(root)
        #expect(relaunched.drops.first { $0.id == Self.textID }?.format == nil)
    }

    @Test func aFailedFormatChangeKeepsTheOldFormatAndShowsAnError() async throws {
        let root = try copyStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = await loaded(root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("drops/\(Self.textID)"))
        await model.setFormat(.set(.plain, codeLanguage: nil), for: Self.textID)
        #expect(model.drops.first { $0.id == Self.textID }?.format == nil)
        #expect(model.alertMessage != nil)
    }

    @Test(arguments: ["https://example.com/a", "http://example.com", "mailto:a@example.com"])
    func webAndMailLinksOpen(link: String) async throws {
        var opened: [URL] = []
        let model = LibraryModel(storageRoot: { URL(fileURLWithPath: "/nonexistent") }, openURL: { opened.append($0) })
        model.openLink(try #require(URL(string: link)))
        #expect(opened == [URL(string: link)])
    }

    @Test(arguments: ["file:///Applications/Calculator.app", "javascript:alert(1)", "x-apple.systempreferences:foo"])
    func otherSchemesDoNotOpen(link: String) async throws {
        var opened: [URL] = []
        let model = LibraryModel(storageRoot: { URL(fileURLWithPath: "/nonexistent") }, openURL: { opened.append($0) })
        model.openLink(try #require(URL(string: link)))
        #expect(opened.isEmpty)
    }
}
