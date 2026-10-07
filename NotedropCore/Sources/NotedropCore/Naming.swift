import Foundation

/// ID, slug, and title rules (spec section 1.4).
public enum Naming {
    public static let maxSlugLength = 48
    public static let maxTitleLength = 80

    public static func slug(_ title: String) -> String {
        var out = ""
        var pendingDash = false
        for scalar in title.unicodeScalars {
            if out.count >= maxSlugLength { break }
            let lowered = Character(scalar).lowercased()
            if scalar.isASCII, lowered.allSatisfy({ $0.isLetter || $0.isNumber }) {
                if pendingDash, !out.isEmpty { out.append("-") }
                pendingDash = false
                if out.count < maxSlugLength { out.append(lowered) }
            } else {
                pendingDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "drop" : trimmed
    }

    public static func dropID(date: Date, title: String) -> String {
        let p = Timestamp.components(date)
        return String(
            format: "%04d-%02d-%02d_%02d%02d%02d_%09d_%@",
            p.year, p.month, p.day, p.hour, p.minute, p.second, p.nanosecond, slug(title))
    }

    /// Rejects empty IDs and anything that could escape the drops folder.
    public static func isValidDropID(_ id: String) -> Bool {
        !id.isEmpty && id != "." && !id.contains("/") && !id.contains("\\") && !id.contains("..")
    }

    /// First non-empty of: explicit title, window title, app name, first non-empty body line, `fallback`.
    public static func inferTitle(
        explicit: String? = nil,
        windowTitle: String? = nil,
        appName: String? = nil,
        text: String? = nil,
        fallback: String = "Untitled Drop"
    ) -> String {
        let firstLine = text?
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let candidates = [explicit, windowTitle, appName, firstLine, fallback]
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return String(value.prefix(maxTitleLength))
            }
        }
        return fallback
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
