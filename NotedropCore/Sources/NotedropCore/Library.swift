import Foundation

public enum TypeFilter: Sendable { case all, text, image }
public enum DateRange: Sendable { case all, today, last7Days, last30Days }

/// Search and filters for the Library list (spec section 1.6). All conditions combine with AND.
public struct LibraryFilter: Sendable {
    public var search: String
    public var type: TypeFilter
    public var tag: String?
    public var app: String?
    public var dateRange: DateRange

    public init(search: String = "", type: TypeFilter = .all, tag: String? = nil, app: String? = nil, dateRange: DateRange = .all) {
        self.search = search; self.type = type; self.tag = tag; self.app = app; self.dateRange = dateRange
    }

    public func apply(_ drops: [Drop], now: Date = Date(), calendar: Calendar = .current) -> [Drop] {
        drops.filter { matches($0, now: now, calendar: calendar) }
    }

    public func matches(_ drop: Drop, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        matchesType(drop) && (tag.map { drop.tags.contains($0) } ?? true)
            && (app.map { drop.source.appName == $0 } ?? true)
            && matchesDate(drop, now: now, calendar: calendar) && matchesSearch(drop)
    }

    private func matchesType(_ drop: Drop) -> Bool {
        switch type {
        case .all: true
        case .text: drop.type == .text
        case .image: drop.type == .image
        }
    }

    private func matchesSearch(_ drop: Drop) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return true }
        let fields: [String?] = [
            drop.title, drop.text, drop.note, drop.imagePath, drop.source.appName,
            drop.source.windowTitle, drop.source.url,
        ]
        return (fields.compactMap { $0 } + drop.tags).contains { $0.lowercased().contains(query) }
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
