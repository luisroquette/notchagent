import Foundation

enum Format {
    /// 950 → "950", 12_400 → "12.4k", 3_400_000 → "3.4M"
    static func tokens(_ n: Int) -> String {
        let value = Double(n)
        switch value {
        case ..<1_000: return String(n)
        case ..<1_000_000: return trimmed(value / 1_000) + "k"
        case ..<1_000_000_000: return trimmed(value / 1_000_000) + "M"
        default: return trimmed(value / 1_000_000_000) + "B"
        }
    }

    static func percent(_ v: Double) -> String {
        "\(Int(v.rounded()))%"
    }

    static func usd(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }

    static func relative(_ date: Date, reference: Date = Date()) -> String {
        let seconds = reference.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: reference)
    }

    /// "2h 14m" until `date`; "now" when past.
    static func countdown(to date: Date, from reference: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(reference)
        guard seconds > 0 else { return "now" }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 48 { return "\(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Local wall-clock time, e.g. "16:40".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private static func trimmed(_ value: Double) -> String {
        let s = String(format: "%.1f", value)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

extension Date {
    /// Floors to the start of the hour (UTC-independent, epoch math).
    var flooredToHour: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    var flooredToDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}

enum Timestamps {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func parseISO8601(_ string: String) -> Date? {
        (try? fractional.parse(string)) ?? (try? plain.parse(string))
    }
}
