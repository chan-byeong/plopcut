import Foundation
import PlopcutCore

enum Formatting {
    static func time(_ createdAt: String) -> String {
        guard let date = Timestamp.parse(createdAt) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func dateTime(_ stamp: String) -> String {
        guard let date = Timestamp.parse(stamp) else { return stamp }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// One-line preview: body, note, window title, URL, image path, app name, else "No preview" (kept English; spec 2.5).
    static func preview(_ drop: Drop) -> String {
        let candidates = [drop.text, drop.note, drop.source.windowTitle, drop.source.url, drop.imagePath, drop.source.appName]
        for candidate in candidates {
            if let line = candidate?.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) {
                return line
            }
        }
        return "No preview"
    }

    /// "3 drops", with the English singular for one (Korean has no plural form).
    static func dropCount(_ count: Int) -> String {
        count == 1 ? L10n.t("dropCountOne") : L10n.t("dropCount", ["count": String(count)])
    }

    /// How a tag is shown everywhere (`#design`). The stored value never has the `#` (spec 5, checklist U-04).
    static func tag(_ tag: String) -> String { "#\(tag)" }

    /// What VoiceOver reads for a list row: title, type, time, preview, app and tags as one phrase.
    static func rowAccessibilityLabel(_ drop: Drop) -> String {
        var parts = [drop.title, L10n.t(drop.type == .image ? "image" : "text"), time(drop.createdAt), preview(drop)]
        if let app = drop.source.appName { parts.append(app) }
        if !drop.tags.isEmpty { parts.append(drop.tags.map(tag).joined(separator: " ")) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func groupTitle(_ group: DateGroup) -> String {
        switch group {
        case .today: L10n.t("today")
        case .yesterday: L10n.t("yesterday")
        case .last7Days: L10n.t("previous7")
        case .earlier: L10n.t("older")
        }
    }
}
