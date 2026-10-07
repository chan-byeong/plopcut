import Foundation

/// UTC timestamps with exactly nine fractional digits so string order equals time order (checklist S-05).
public enum Timestamp {
    public static func format(_ date: Date) -> String {
        let parts = components(date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%09dZ",
            parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second, parts.nanosecond)
    }

    /// Accepts any number of fractional digits (including none).
    public static func parse(_ string: String) -> Date? {
        guard string.hasSuffix("Z") else { return nil }
        let body = string.dropLast()
        let halves = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = halves.first else { return nil }
        let fields = whole.split(whereSeparator: { "-T:".contains($0) })
        guard fields.count == 6, let nums = Optional(fields.compactMap { Int($0) }), nums.count == 6 else { return nil }
        var parts = DateComponents()
        parts.year = nums[0]; parts.month = nums[1]; parts.day = nums[2]
        parts.hour = nums[3]; parts.minute = nums[4]; parts.second = nums[5]
        parts.timeZone = utc.timeZone
        guard let base = utc.date(from: parts) else { return nil }
        guard halves.count == 2 else { return base }
        let digits = halves[1]
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        let fraction = Double("0." + digits) ?? 0
        return base.addingTimeInterval(fraction)
    }

    struct Parts {
        var year, month, day, hour, minute, second, nanosecond: Int
    }

    /// Date carries about microsecond precision at current epochs, so round to microseconds
    /// to keep the output stable instead of printing floating-point noise.
    static func components(_ date: Date) -> Parts {
        let micros = (date.timeIntervalSince1970 * 1_000_000).rounded()
        let seconds = (micros / 1_000_000).rounded(.down)
        let fractionMicros = Int(micros - seconds * 1_000_000)
        let whole = Date(timeIntervalSince1970: seconds)
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: whole)
        return Parts(
            year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1,
            hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0,
            nanosecond: fractionMicros * 1000)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
