import Foundation
import Testing
@testable import NotedropCore

@Suite struct TimestampTests {
    @Test func formatsUTCWithNineFractionDigits() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(Timestamp.format(date) == "1970-01-01T00:00:00.000000000Z")
    }

    @Test func stringOrderMatchesTimeOrder() {
        let a = Date(timeIntervalSince1970: 100.5)
        let b = Date(timeIntervalSince1970: 100.25)
        let c = Date(timeIntervalSince1970: 1000)
        let sorted = [a, b, c].sorted { Timestamp.format($0) < Timestamp.format($1) }
        #expect(sorted == [b, a, c])
        #expect(Timestamp.format(a).count == Timestamp.format(c).count)
    }

    @Test func parsesAnyFractionLength() throws {
        let d9 = try #require(Timestamp.parse("2026-01-01T09:00:00.000000001Z"))
        let d0 = try #require(Timestamp.parse("2026-01-01T09:00:00Z"))
        let d3 = try #require(Timestamp.parse("2026-01-01T09:00:00.500Z"))
        #expect(d9.timeIntervalSince(d0) < 0.001)
        #expect(abs(d3.timeIntervalSince(d0) - 0.5) < 0.0001)
        #expect(Timestamp.parse("garbage") == nil)
    }
}

@Suite struct SlugAndIdTests {
    @Test func slugRules() {
        #expect(Naming.slug("Hello, World!") == "hello-world")
        #expect(Naming.slug("한글 제목") == "drop")
        #expect(Naming.slug("  --Cursor***App--  ") == "cursor-app")
        #expect(Naming.slug("") == "drop")
        let long = Naming.slug(String(repeating: "a", count: 100))
        #expect(long.count == 48)
        #expect(!Naming.slug("abc " + String(repeating: "b", count: 60)).hasSuffix("-"))
    }

    @Test func idFormat() {
        #expect(Naming.dropID(date: sampleDate, title: "Cursor") == "2026-10-02_063129_850365000_cursor")
    }

    @Test func idValidation() {
        #expect(Naming.isValidDropID("2026-10-02_063129_850365000_cursor"))
        for bad in ["", ".", "a/b", "a\\b", "..", "x..y"] { #expect(!Naming.isValidDropID(bad)) }
    }
}

@Suite struct TitleTests {
    @Test func priority() {
        #expect(Naming.inferTitle(explicit: " Mine ", windowTitle: "W", appName: "A", text: "T") == "Mine")
        #expect(Naming.inferTitle(windowTitle: "W", appName: "A", text: "T") == "W")
        #expect(Naming.inferTitle(windowTitle: "  ", appName: "A", text: "T") == "A")
        #expect(Naming.inferTitle(text: "\n\n  First line \nsecond") == "First line")
        #expect(Naming.inferTitle() == "Untitled Drop")
        #expect(Naming.inferTitle(fallback: "Image Drop") == "Image Drop")
    }

    @Test func truncatesTo80() {
        let title = Naming.inferTitle(explicit: String(repeating: "x", count: 200))
        #expect(title.count == 80)
    }
}

@Suite struct TagTests {
    @Test func normalizes() {
        #expect(Tags.normalize(["#Research", "research", " Swift ", "", "##Two Words"]) == ["research", "swift", "two words"])
    }

    @Test func parsesCommaInput() {
        #expect(Tags.parse("a, #B ,, a, c") == ["a", "b", "c"])
    }

    @Test func recentTagsMergeAndCap() {
        let recent = (1...12).map { "t\($0)" }
        let merged = Tags.mergeRecent(new: ["x", "t3"], existing: recent)
        #expect(merged.count == 12)
        #expect(merged.prefix(3) == ["x", "t3", "t1"])
    }
}
