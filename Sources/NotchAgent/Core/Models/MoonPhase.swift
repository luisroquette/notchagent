import Foundation

/// The Moon's current illumination phase, computed from its synodic age —
/// the same math that drives the Apple Weather moon. No API, no tables.
public enum MoonPhase: Sendable {
    /// 0...1 continuous illumination: 0 = new, 0.25 = first quarter,
    /// 0.5 = full, 0.75 = last quarter.
    public static func illumination(at date: Date) -> Double {
        let synodicMonth = 29.530588853
        // Reference new moon: 2000-01-06 18:14 UTC (Julian day 2451550.1).
        let jd = Self.julianDay(date)
        let daysSinceNew = (jd - 2_451_550.1) / synodicMonth
        let phase = daysSinceNew - floor(daysSinceNew)
        return phase
    }

    /// Fraction of the disc that is lit (0 at new moon, 1 at full).
    public static func litFraction(at date: Date) -> Double {
        // Illuminated fraction follows (1 - cos(2π·phase)) / 2.
        let phase = illumination(at: date)
        return (1 - cos(2 * .pi * phase)) / 2
    }

    /// Simple human label from the continuous phase.
    public enum Label: String, Sendable {
        case newMoon, waxingCrescent, firstQuarter, waxingGibbous
        case fullMoon, waningGibbous, lastQuarter, waningCrescent
    }

    public static func label(at date: Date) -> Label {
        let phase = illumination(at: date)
        switch phase {
        case ..<0.0625: return .newMoon
        case ..<0.1875: return .waxingCrescent
        case ..<0.3125: return .firstQuarter
        case ..<0.4375: return .waxingGibbous
        case ..<0.5625: return .fullMoon
        case ..<0.6875: return .waningGibbous
        case ..<0.8125: return .lastQuarter
        case ..<0.9375: return .waningCrescent
        default: return .newMoon
        }
    }

    /// Julian day number (UTC) — the astronomy standard time scale.
    static func julianDay(_ date: Date) -> Double {
        let seconds = date.timeIntervalSince1970
        return seconds / 86_400 + 2_440_587.5
    }
}
