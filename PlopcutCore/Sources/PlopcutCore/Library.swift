import Foundation

public enum TypeFilter: Sendable { case all, text, image }
public enum DateRange: Sendable { case all, today, last7Days, last30Days }

/// Search and filters for the Library list (spec section 1.6). All conditions combine with AND; the selected
/// sources combine with OR among themselves, and an empty set sets no condition.
public struct LibraryFilter: Sendable {
    public var search: String
    public var type: TypeFilter
    public var tag: String?
    public var sources: Set<SourceKey>
    public var dateRange: DateRange

    public init(search: String = "", type: TypeFilter = .all, tag: String? = nil, sources: Set<SourceKey> = [], dateRange: DateRange = .all) {
        self.search = search; self.type = type; self.tag = tag; self.sources = sources; self.dateRange = dateRange
    }

    /// With an `index` built from the same drops, search runs on prebuilt lowercase text instead of rebuilding it per keystroke.
    public func apply(_ drops: [Drop], now: Date = Date(), calendar: Calendar = .current, index: SearchIndex? = nil) -> [Drop] {
        let query = normalizedQuery
        let needle = index == nil ? nil : SearchIndex.needle(query)
        return drops.filter { drop in
            if let index, let needle {
                return matchesIgnoringSearch(drop, now: now, calendar: calendar) && index.contains(needle, in: drop.id)
            }
            return matches(drop, now: now, calendar: calendar)
        }
    }

    public func matches(_ drop: Drop, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        matchesIgnoringSearch(drop, now: now, calendar: calendar) && matchesSearch(drop)
    }

    private var normalizedQuery: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matchesIgnoringSearch(_ drop: Drop, now: Date, calendar: Calendar) -> Bool {
        matchesType(drop) && (tag.map { drop.tags.contains($0) } ?? true)
            && (sources.isEmpty || SourceKey(drop.source).map(sources.contains) == true)
            && matchesDate(drop, now: now, calendar: calendar)
    }

    private func matchesType(_ drop: Drop) -> Bool {
        switch type {
        case .all: true
        case .text: drop.type == .text
        case .image: drop.type == .image
        }
    }

    private func matchesSearch(_ drop: Drop) -> Bool {
        let query = SearchIndex.fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        if query.isEmpty { return true }
        let fields: [String?] = [
            drop.title, drop.text, drop.note, drop.imagePath, drop.source.appName,
            drop.source.windowTitle, drop.source.url,
        ]
        return (fields.compactMap { $0 } + drop.tags).contains { SearchIndex.fold($0).contains(query) }
    }

    private func matchesDate(_ drop: Drop, now: Date, calendar: Calendar) -> Bool {
        if dateRange == .all { return true }
        guard let created = Timestamp.parse(drop.createdAt) else { return false }
        switch dateRange {
        case .all: return true
        case .today: return calendar.isDate(created, inSameDayAs: now)
        case .last7Days: return created >= now.addingTimeInterval(-7 * 86_400)
        case .last30Days: return created >= now.addingTimeInterval(-30 * 86_400)
        }
    }

    /// Keeps `current` if it is still listed, otherwise the first item, otherwise nothing.
    public static func resolveSelection(_ current: String?, in drops: [Drop]) -> String? {
        if let current, drops.contains(where: { $0.id == current }) { return current }
        return drops.first?.id
    }
}

/// Lowercased searchable text of every drop, built once per scan so each keystroke is a byte search (STA-80).
/// Fields are joined by NUL so a query never matches across two fields. Fields and the query go through the same
/// `fold` (lowercase, then NFC), so decomposed (NFD) and precomposed Hangul match each other (STA-82).
public struct SearchIndex: Sendable {
    private var haystacks: [String: [UInt8]] = [:]

    public init(_ drops: [Drop] = []) {
        haystacks.reserveCapacity(drops.count)
        for drop in drops { insert(drop) }
    }

    public mutating func insert(_ drop: Drop) {
        let fields: [String?] = [
            drop.title, drop.text, drop.note, drop.imagePath, drop.source.appName,
            drop.source.windowTitle, drop.source.url,
        ]
        var bytes: [UInt8] = []
        for field in fields.compactMap({ $0 }) + drop.tags {
            bytes.append(contentsOf: Self.fold(field).utf8)
            bytes.append(0)
        }
        haystacks[drop.id] = bytes
    }

    public mutating func remove(id: String) { haystacks[id] = nil }

    /// Search form of a field or query: lowercased, then NFC so canonically equivalent text has the same bytes.
    /// ASCII text is already NFC, so it skips the normalization call.
    static func fold(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.utf8.allSatisfy({ $0 < 0x80 }) { return lower }
        return lower.precomposedStringWithCanonicalMapping
    }

    /// The folded query as bytes; empty means "match everything".
    static func needle(_ trimmedQuery: String) -> [UInt8] { Array(fold(trimmedQuery).utf8) }

    func contains(_ needle: [UInt8], in id: String) -> Bool {
        if needle.isEmpty { return true }
        guard let hay = haystacks[id] else { return false }
        return hay.withUnsafeBufferPointer { h in
            needle.withUnsafeBufferPointer { n in
                guard let hb = h.baseAddress, let nb = n.baseAddress else { return false }
                return memmem(hb, h.count, nb, n.count) != nil
            }
        }
    }
}

public enum DateGroup: CaseIterable, Sendable {
    case today, yesterday, last7Days, earlier

    public static func group(_ drops: [Drop], now: Date = Date(), calendar: Calendar = .current) -> [(group: DateGroup, drops: [Drop])] {
        var buckets: [DateGroup: [Drop]] = [:]
        for drop in drops { buckets[of(drop, now: now, calendar: calendar), default: []].append(drop) }
        return allCases.compactMap { group in buckets[group].map { (group, $0) } }
    }

    static func of(_ drop: Drop, now: Date, calendar: Calendar) -> DateGroup {
        guard let created = Timestamp.parse(drop.createdAt) else { return .earlier }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: created), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .yesterday
        case 2...7: return .last7Days
        default: return .earlier
        }
    }
}
