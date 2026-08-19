import Foundation

/// The fan of moments and their weights — "sem anúncio": low weights mean
/// the mascot often just carries on.
public enum DelightCatalog {
    /// One reaction per 90s at most.
    public static let reactionCooldown: TimeInterval = 90

    public static func weight(for moment: DelightMoment) -> Double {
        switch moment {
        case .quotaReset: 0.9
        case .firstExpandOfDay: 0.8
        case .peakPassed: 0.7
        case .midnight: 0.6
        case .idleThirtySeconds: 0.4
        case .randomExpand: 0.3
        }
    }

    public static func gestures(for moment: DelightMoment) -> [MascotGesture] {
        switch moment {
        case .quotaReset: [.nod, .hop]
        case .firstExpandOfDay: [.lookAtCursor, .tilt]
        case .peakPassed: [.stretch, .blink]
        case .midnight: [.yawn, .blink]
        case .idleThirtySeconds: [.lookAtCursor, .blink]
        case .randomExpand: [.blink, .hop, .tilt, .stretch]
        }
    }

    public static func affectionBump(firstExpandOfDay: Bool) -> Double {
        firstExpandOfDay ? 0.02 : 0
    }

    /// Being ignored for days cools the mascot off — capped so it never
    /// becomes unreachable.
    public static func affectionAbsencePenalty(absentDays: Int) -> Double {
        Double(min(max(absentDays, 0), 5)) * 0.01
    }
}
