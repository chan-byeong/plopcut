import Foundation

/// Tag normalization (spec section 1.5).
public enum Tags {
    public static let maxRecent = 12

    public static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while value.hasPrefix("#") { value.removeFirst() }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value.isEmpty || !seen.insert(value).inserted { continue }
            result.append(value)
        }
        return result
    }

    public static func parse(_ input: String) -> [String] {
        normalize(input.split(separator: ",", omittingEmptySubsequences: false).map(String.init))
    }

    public static func limitedRecent(_ tags: [String]) -> [String] {
        Array(normalize(tags).prefix(maxRecent))
    }

    public static func mergeRecent(new: [String], existing: [String]) -> [String] {
        limitedRecent(new + existing)
    }
}
