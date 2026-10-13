import Foundation
import Testing
@testable import PlopcutCore

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}
private let now = Timestamp.parse("2026-03-10T12:00:00Z")!

private func drop(_ id: String, created: String, type: DropType = .text, title: String = "t", text: String? = nil,
                  note: String? = nil, tags: [String] = [], source: DropSource = DropSource(), imagePath: String? = nil) -> Drop {
    Drop(id: id, type: type, title: title, text: text, imagePath: imagePath, source: source, note: note,
         tags: tags, createdAt: created, updatedAt: created)
}

@Suite struct SearchTests {
    @Test func matchesEveryField() {
        let d = drop("1", created: "2026-03-10T00:00:00Z", title: "Alpha", text: "Body Gamma", note: "Delta note",
                     tags: ["epsilon"], source: DropSource(appName: "Zeta", windowTitle: "Eta win", url: "https://theta.dev", filePath: nil),
                     imagePath: "image.png")
        for q in ["alpha", "GAMMA", "delta", "epsilon", "zeta", "eta win", "theta.dev", "image.png", "  alpha  "] {
            #expect(LibraryFilter(search: q).matches(d, now: now, calendar: cal), "\(q)")
        }
        #expect(!LibraryFilter(search: "nope").matches(d, now: now, calendar: cal))
        #expect(LibraryFilter(search: "   ").matches(d, now: now, calendar: cal))
    }

    @Test func filtersCombineWithAnd() {
        let a = drop("a", created: "2026-03-10T01:00:00Z", type: .text, tags: ["x"], source: DropSource(appName: "App1"))
        let b = drop("b", created: "2026-03-10T02:00:00Z", type: .image, tags: ["x"], source: DropSource(appName: "App2"))
        let all = [a, b]
        #expect(LibraryFilter(type: .image).apply(all, now: now, calendar: cal).map(\.id) == ["b"])
        #expect(LibraryFilter(tag: "x").apply(all, now: now, calendar: cal).count == 2)
        #expect(LibraryFilter(tag: "x", app: "App1").apply(all, now: now, calendar: cal).map(\.id) == ["a"])
        #expect(LibraryFilter(tag: "y").apply(all, now: now, calendar: cal).isEmpty)
    }
}

@Suite struct DateFilterTests {
    @Test func today7And30() {
        let today = drop("t", created: "2026-03-10T00:00:01Z")
        let sixDays = drop("s", created: "2026-03-04T13:00:00Z")
        let eightDays = drop("e", created: "2026-03-02T11:00:00Z")
        let old = drop("o", created: "2026-01-01T00:00:00Z")
        let bad = drop("b", created: "not a date")
        let all = [today, sixDays, eightDays, old, bad]
        func ids(_ range: DateRange) -> [String] { LibraryFilter(dateRange: range).apply(all, now: now, calendar: cal).map(\.id) }
        #expect(ids(.today) == ["t"])
        #expect(ids(.last7Days) == ["t", "s"])
        #expect(ids(.last30Days) == ["t", "s", "e"])
        #expect(ids(.all).count == 5)
    }
}

@Suite struct GroupingTests {
    @Test func groupsByCalendarDayAndHidesEmpty() {
        let drops = [
            drop("today", created: "2026-03-10T00:30:00Z"),
            drop("yesterday", created: "2026-03-09T23:59:00Z"),
            drop("two", created: "2026-03-08T10:00:00Z"),
            drop("seven", created: "2026-03-03T10:00:00Z"),
            drop("eight", created: "2026-03-02T10:00:00Z"),
            drop("bad", created: "???"),
        ]
        let groups = DateGroup.group(drops, now: now, calendar: cal)
        #expect(groups.map(\.group) == [.today, .yesterday, .last7Days, .earlier])
        #expect(groups[2].drops.map(\.id) == ["two", "seven"])
        #expect(groups[3].drops.map(\.id) == ["eight", "bad"])
        #expect(DateGroup.group([], now: now, calendar: cal).isEmpty)
    }
}

@Suite struct SelectionTests {
    @Test func keepsOrFallsBack() {
        let list = [drop("a", created: "x"), drop("b", created: "x")]
        #expect(LibraryFilter.resolveSelection("b", in: list) == "b")
        #expect(LibraryFilter.resolveSelection("gone", in: list) == "a")
        #expect(LibraryFilter.resolveSelection(nil, in: list) == "a")
        #expect(LibraryFilter.resolveSelection("a", in: []) == nil)
    }
}

@Suite struct SearchIndexTests {
    @Test func indexedSearchAgreesWithDirectSearch() {
        let drops = [
            drop("1", created: "2026-03-10T00:00:00Z", title: "Alpha", text: "Body Gamma", note: "Delta note", tags: ["Epsilon"],
                 source: DropSource(appName: "Zeta", windowTitle: "Eta win", url: "https://theta.dev", filePath: nil), imagePath: "image.png"),
            drop("2", created: "2026-03-10T00:00:00Z", title: "라이브러리 검색", text: nil, tags: ["태그"]),
            drop("3", created: "2026-03-10T00:00:00Z", title: "ab", text: "cd"),
        ]
        let index = SearchIndex(drops)
        for q in ["alpha", "GAMMA", "  delta  ", "epsilon", "zeta", "theta.dev", "image.png", "라이브러리", "태그", "nope", "", "   ", "bc", "abcd"] {
            let filter = LibraryFilter(search: q)
            #expect(filter.apply(drops, now: now, calendar: cal, index: index).map(\.id)
                == filter.apply(drops, now: now, calendar: cal).map(\.id), "\(q)")
        }
    }

    @Test func decomposedAndPrecomposedHangulMatchEachOther() {
        func nfd(_ s: String) -> String { s.decomposedStringWithCanonicalMapping }
        func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
        let decomposed = [
            drop("title", created: "2026-03-10T00:00:00Z", title: nfd("자모분리 제목")),
            drop("body", created: "2026-03-10T00:00:00Z", title: "x", text: nfd("자모분리 테스트 문장")),
            drop("note", created: "2026-03-10T00:00:00Z", title: "x", note: nfd("노트 메모")),
            drop("tag", created: "2026-03-10T00:00:00Z", title: "x", tags: [nfd("한글태그")]),
        ]
        let precomposed = [drop("nfc", created: "2026-03-10T00:00:00Z", title: "x", text: nfc("완성형 본문 Café"))]
        #expect(nfd("자모분리").utf8.count != nfc("자모분리").utf8.count)
        let cases: [(drops: [Drop], query: String, id: String)] = [
            (decomposed, nfc("제목"), "title"), (decomposed, nfc("테스트"), "body"),
            (decomposed, nfc("메모"), "note"), (decomposed, nfc("한글태그"), "tag"),
            (precomposed, nfd("완성형"), "nfc"), (precomposed, nfd("CAFÉ"), "nfc"),
        ]
        for (drops, query, id) in cases {
            var incremental = SearchIndex()
            drops.forEach { incremental.insert($0) }
            for index in [SearchIndex(drops), incremental] {
                #expect(LibraryFilter(search: query).apply(drops, now: now, calendar: cal, index: index).map(\.id) == [id], "\(query)")
            }
            #expect(LibraryFilter(search: query).apply(drops, now: now, calendar: cal).map(\.id) == [id], "\(query)")
        }
    }

    @Test func removedAndUnindexedDropsDoNotMatch() {
        let a = drop("1", created: "2026-03-10T00:00:00Z", title: "Alpha")
        var index = SearchIndex([a])
        index.remove(id: "1")
        #expect(LibraryFilter(search: "alpha").apply([a], index: index).isEmpty)
        #expect(LibraryFilter().apply([a], index: index).count == 1)
    }

    @Test func fastTimestampParseMatchesCalendarParse() {
        for s in ["2026-03-10T12:00:00Z", "2026-03-10T12:00:00.5Z", "2026-01-01T09:00:00.000000001Z", "2024-02-28T23:59:59.999999999Z",
                  "2026-12-28T00:00:00.123456Z", "1970-01-01T00:00:00Z"] {
            #expect(Timestamp.parse(s) == Timestamp.slowParse(s), "\(s)")
        }
        for s in ["", "2026-03-10", "2026-13-10T00:00:00Z", "2026-03-10T00:00:00.Z", "2026-03-10T00:00:00", "garbage-----------Z"] {
            #expect(Timestamp.parse(s) == Timestamp.slowParse(s), "\(s)")
        }
    }
}
