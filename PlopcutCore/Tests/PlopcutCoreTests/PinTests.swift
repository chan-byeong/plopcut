import Foundation
import Testing
@testable import PlopcutCore

private let pinDate = Date(timeIntervalSince1970: 1_790_930_000)

/// A store whose clock can be moved forward between calls.
private final class Clock: @unchecked Sendable {
    var now = sampleDate
}

private func makeStore(_ root: URL, clock: Clock) -> DropStore {
    DropStore(root: root, clock: { clock.now })
}

private func json(_ url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func metadataURL(_ root: URL, _ id: String) -> URL {
    root.appendingPathComponent("drops/\(id)/drop.json")
}

// S-21, S-22: pinning writes `pinnedAt`, unpinning clears it, and neither changes `updatedAt` (spec 1.2).
@Suite struct DropStorePinTests {
    @Test func pinAndUnpinRoundTripWithoutTouchingUpdatedAt() throws {
        let root = try tempDir()
        let clock = Clock()
        let store = makeStore(root, clock: clock)
        let saved = try store.saveText("body", title: "T", source: DropSource(), tags: [], note: nil)
        #expect(saved.pinnedAt == nil)
        #expect(try json(metadataURL(root, saved.id))["pinnedAt"] is NSNull)

        clock.now = pinDate
        let pinned = try store.update(id: saved.id, DropUpdate(pinned: true))
        #expect(pinned.pinnedAt == "2026-10-02T08:33:20.000000000Z")
        #expect(pinned.updatedAt == saved.updatedAt)
        #expect(try store.scan().drops.first?.pinnedAt == pinned.pinnedAt)
        #expect(try json(metadataURL(root, saved.id))["pinnedAt"] as? String == pinned.pinnedAt)

        // Pinning again keeps the first pin time.
        clock.now = pinDate.addingTimeInterval(60)
        #expect(try store.update(id: saved.id, DropUpdate(pinned: true)).pinnedAt == pinned.pinnedAt)

        let unpinned = try store.update(id: saved.id, DropUpdate(pinned: false))
        #expect(unpinned.pinnedAt == nil)
        #expect(unpinned.updatedAt == saved.updatedAt)
        #expect(try json(metadataURL(root, saved.id))["pinnedAt"] is NSNull)
    }

    @Test func editingContentKeepsThePinAndUpdatesUpdatedAt() throws {
        let root = try tempDir()
        let clock = Clock()
        let store = makeStore(root, clock: clock)
        let saved = try store.saveText("body", title: "T", source: DropSource(), tags: [], note: nil, pinned: true)
        clock.now = pinDate
        let edited = try store.update(id: saved.id, DropUpdate(title: "New"))
        #expect(edited.pinnedAt == saved.pinnedAt)
        #expect(edited.updatedAt != saved.updatedAt)
    }

    // S-23: "save and pin" (PLO-105) stores the drop already pinned, at its creation time.
    @Test func textAndImageDropsCanBeSavedPinned() throws {
        let root = try tempDir()
        let store = makeStore(root, clock: Clock())
        let text = try store.saveText("body", title: "T", source: DropSource(), tags: [], note: nil, pinned: true)
        #expect(text.pinnedAt == text.createdAt)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])
        let image = try store.saveImage(png, title: nil, source: DropSource(), tags: [], note: nil, pinned: true)
        #expect(image.pinnedAt == image.createdAt)
        let unpinned = try store.saveText("other", title: "U", source: DropSource(), tags: [], note: nil)
        #expect(unpinned.pinnedAt == nil)
    }

    // S-21: legacy drop.json files without the key read as not pinned; the pinned fixture keeps its time.
    @Test func fixturesReadPinnedStateAndLegacyFilesReadAsNotPinned() throws {
        let drops = try makeStore(Fixtures.copyStorage(), clock: Clock()).scan().drops
        let byID = Dictionary(uniqueKeysWithValues: drops.map { ($0.id, $0) })
        #expect(byID["2026-01-03_110000_000000003_image-drop"]?.pinnedAt == "2026-01-03T12:00:00.000000003Z")
        #expect(byID["2026-01-04_120000_000000000_legacy-minimal-text"]?.pinnedAt == nil)
        #expect(byID["2026-01-01_090000_000000001_example-app"]?.pinnedAt == nil)
    }
}

// L-16: the "Pinned" section sits before the date groups, newest pin first, and pinned drops are not repeated.
@Suite struct ListSectionTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let now = Timestamp.parse("2026-03-10T12:00:00Z")!

    private func drop(_ id: String, created: String, pinned: String? = nil, tags: [String] = []) -> Drop {
        Drop(id: id, type: .text, title: id, text: id, tags: tags, createdAt: created, updatedAt: created, pinnedAt: pinned)
    }

    @Test func pinnedDropsComeFirstByPinTimeAndAreNotRepeated() {
        let drops = [
            drop("d", created: "2026-03-10T09:00:00Z"),
            drop("c", created: "2026-03-10T08:00:00Z", pinned: "2026-03-10T10:00:00Z"),
            drop("b", created: "2026-03-09T08:00:00Z", pinned: "2026-03-10T11:00:00Z"),
            drop("a2", created: "2026-03-01T08:00:00Z", pinned: "2026-03-10T10:00:00Z"),
            drop("a", created: "2026-03-01T07:00:00Z"),
        ]
        let sections = ListSection.make(drops, now: now, calendar: cal)
        #expect(sections.map(\.section) == [.pinned, .date(.today), .date(.earlier)])
        // Same pin time: higher id first ("c" > "a2").
        #expect(sections.map { $0.drops.map(\.id) } == [["b", "c", "a2"], ["d"], ["a"]])
    }

    @Test func withoutPinsThereIsNoPinnedSection() {
        let sections = ListSection.make([drop("a", created: "2026-03-10T09:00:00Z")], now: now, calendar: cal)
        #expect(sections.map(\.section) == [.date(.today)])
    }

    @Test func thePinnedSectionFollowsTheFilter() {
        let drops = [
            drop("x", created: "2026-03-10T09:00:00Z", pinned: "2026-03-10T10:00:00Z", tags: ["keep"]),
            drop("y", created: "2026-03-10T08:00:00Z", pinned: "2026-03-10T11:00:00Z"),
        ]
        let filtered = LibraryFilter(tag: "keep").apply(drops, now: now, calendar: cal)
        #expect(ListSection.make(filtered, now: now, calendar: cal).map { $0.drops.map(\.id) } == [["x"]])
    }

    // L-17: the Pinned collection keeps only pinned drops and combines with search (AND).
    @Test func pinnedOnlyKeepsPinnedDropsAndCombinesWithSearch() {
        let drops = [
            drop("alpha", created: "2026-03-10T09:00:00Z", pinned: "2026-03-10T10:00:00Z"),
            drop("beta", created: "2026-03-10T08:00:00Z", pinned: "2026-03-10T11:00:00Z"),
            drop("gamma", created: "2026-03-10T07:00:00Z"),
        ]
        var filter = LibraryFilter()
        filter.pinnedOnly = true
        #expect(filter.apply(drops, now: now, calendar: cal).map(\.id) == ["alpha", "beta"])
        filter.search = "beta"
        #expect(filter.apply(drops, now: now, calendar: cal, index: SearchIndex(drops)).map(\.id) == ["beta"])
    }
}
