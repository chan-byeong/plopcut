import AppKit
import Testing
@testable import Plopcut

@MainActor
@Suite struct SourceAppIconsTests {
    private final class Counter { var lookups: [String] = [] }

    private func icons(_ counter: Counter, known: Set<String>) -> SourceAppIcons {
        SourceAppIcons(find: { name in
            counter.lookups.append(name)
            return known.contains(name) ? NSImage(size: NSSize(width: 4, height: 4)) : nil
        })
    }

    @Test func aKnownAppGetsItsIcon() {
        let counter = Counter()
        #expect(icons(counter, known: ["Google Chrome"]).icon(forAppNamed: "Google Chrome") != nil)
    }

    @Test func anUnknownOrMissingNameGetsNoIconSoTheTypeIconStays() {
        let counter = Counter()
        let subject = icons(counter, known: ["Google Chrome"])
        #expect(subject.icon(forAppNamed: "Gone App") == nil)
        #expect(subject.icon(forAppNamed: nil) == nil)
        #expect(subject.icon(forAppNamed: "  ") == nil)
        #expect(counter.lookups == ["Gone App"])  // a blank name is not looked up at all
    }

    @Test func eachNameIsLookedUpOnceEvenWhenNothingWasFound() {
        let counter = Counter()
        let subject = icons(counter, known: ["Google Chrome"])
        for _ in 0..<3 {
            _ = subject.icon(forAppNamed: "Google Chrome")
            _ = subject.icon(forAppNamed: "Gone App")
        }
        #expect(counter.lookups == ["Google Chrome", "Gone App"])
    }

    private func appFolder(_ names: [String]) throws -> String {
        let dir = NSTemporaryDirectory() + "apps-" + UUID().uuidString
        for name in names {
            try FileManager.default.createDirectory(atPath: dir + "/" + name, withIntermediateDirectories: true)
        }
        return dir
    }

    @Test func theIndexFindsAnAppByItsFileName() throws {
        let dir = try appFolder(["Google Chrome.app"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let index = AppIndex.build(folders: [dir])
        #expect(index.paths["Google Chrome"] == dir + "/Google Chrome.app")
        #expect(index.paths["No Such App"] == nil)
    }

    @Test func aKoreanNameMatchesWhetherItIsComposedOrDecomposed() throws {
        let decomposed = "메모".decomposedStringWithCanonicalMapping + ".app"
        let dir = try appFolder([decomposed])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let index = AppIndex.build(folders: [dir])
        #expect(index.paths["메모".precomposedStringWithCanonicalMapping] != nil)
    }

    @Test func theFirstFolderWinsWhenTwoFoldersHaveTheSameApp() throws {
        let first = try appFolder(["Same.app"])
        let second = try appFolder(["Same.app"])
        defer { try? FileManager.default.removeItem(atPath: first); try? FileManager.default.removeItem(atPath: second) }
        #expect(AppIndex.build(folders: [first, second]).paths["Same"] == first + "/Same.app")
    }

    @Test func noIconIsReturnedBeforeTheIndexIsReady() async throws {
        let dir = try appFolder(["Later.app"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let subject = SourceAppIcons.loading(folders: [dir])
        for _ in 0..<200 where !subject.isReady { try await Task.sleep(for: .milliseconds(10)) }
        #expect(subject.isReady)
        #expect(subject.icon(forAppNamed: "Later") != nil)
        #expect(subject.icon(forAppNamed: "Missing") == nil)
    }

    @Test func theTypeSymbolStillTellsTextFromImage() {
        #expect(DropRow.typeSymbol(for: .text) == "textformat")
        #expect(DropRow.typeSymbol(for: .image) == "photo")
    }
}
