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
        fastParse(string) ?? slowParse(string)
    }

    /// `YYYY-MM-DDTHH:MM:SS[.fraction]Z` with in-range fields, computed without Calendar (about 20x faster; STA-80).
    private static func fastParse(_ string: String) -> Date? {
        var string = string
        return string.withUTF8 { u -> Date? in
            let count = u.count
            guard count >= 20, u[count - 1] == UInt8(ascii: "Z"),
                  u[4] == 45, u[7] == 45, u[10] == 84, u[13] == 58, u[16] == 58 else { return nil }
            func num(_ from: Int, _ to: Int) -> Int? {
                var value = 0
                for i in from..<to {
                    guard u[i] >= 48, u[i] <= 57 else { return nil }
                    value = value * 10 + Int(u[i] - 48)
                }
                return value
            }
            guard let y = num(0, 4), let mo = num(5, 7), let d = num(8, 10),
                  let h = num(11, 13), let mi = num(14, 16), let s = num(17, 19),
                  (1...12).contains(mo), (1...28).contains(d), h < 24, mi < 60, s < 60, y >= 1970 else { return nil }
            var fraction = 0.0
            if count > 20 {
                let digits = count - 21
                guard u[19] == 46, digits >= 1, digits <= 15 else { return nil }
                guard let value = num(20, count - 1) else { return nil }
                fraction = Double(value) / pow(10, Double(digits))
            }
            // Days from civil (Howard Hinnant), valid for the proleptic Gregorian calendar.
            let yy = mo <= 2 ? y - 1 : y
            let era = yy / 400
            let yoe = yy - era * 400
            let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + d - 1
            let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            let days = era * 146_097 + doe - 719_468
            let seconds = Double(days * 86_400 + h * 3600 + mi * 60 + s)
            return Date(timeIntervalSince1970: seconds + fraction)
        }
    }

    static func slowParse(_ string: String) -> Date? {
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
