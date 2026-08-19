import AppKit
import Foundation

/// Pure event detection — nothing here touches timers or the UI.
public enum DelightSignals {
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func crossedMidnight(previous: Date, now: Date, calendar: Calendar = .current) -> Bool {
        dayKey(previous, calendar: calendar) != dayKey(now, calendar: calendar)
    }

    /// A quota reset looks like the remaining percent jumping up ≥ 30 points
    /// between two refreshes of the same provider.
    public static func quotaResetDetected(previous: GaugeMetric?, current: GaugeMetric?) -> Bool {
        guard let previous, let current else { return false }
        return current.remaining - previous.remaining >= 30
    }

    public enum TimeTintKey: String, CaseIterable, Sendable {
        case night, dawn, day, dusk
    }

    public static func timeTint(at date: Date, calendar: Calendar = .current) -> TimeTintKey {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 20...23, 0...4: return .night
        case 5...8: return .dawn
        case 9...16: return .day
        default: return .dusk
        }
    }

    /// Low-opacity washes over the black panel — only when weather is OFF.
    public static func tintColor(for key: TimeTintKey) -> NSColor {
        switch key {
        case .night: NSColor(red: 0.03, green: 0.04, blue: 0.09, alpha: 0.10)
        case .dawn: NSColor(red: 0.55, green: 0.45, blue: 0.62, alpha: 0.08)
        case .day: NSColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 0.04)
        case .dusk: NSColor(red: 0.75, green: 0.45, blue: 0.20, alpha: 0.09)
        }
    }
}
