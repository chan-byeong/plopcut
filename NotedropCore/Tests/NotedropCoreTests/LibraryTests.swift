import Foundation
import Testing
@testable import NotedropCore

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
