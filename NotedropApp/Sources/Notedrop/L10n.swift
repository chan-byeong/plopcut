import Foundation

/// Looks up user-facing text from the generated table. Korean for `ko*` system languages, English otherwise.
enum L10n {
    nonisolated(unsafe) static var languageOverride: String?

    static var isKorean: Bool {
        (languageOverride ?? Locale.preferredLanguages.first ?? "en").hasPrefix("ko")
    }

    static func t(_ key: String, _ values: [String: String] = [:]) -> String {
        guard let entry = StringTable.entries[key] else { return key }
        var text = isKorean ? entry.ko : entry.en
        for (name, value) in values { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
        return text
    }
}
