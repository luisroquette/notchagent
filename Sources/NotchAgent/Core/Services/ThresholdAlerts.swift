import Foundation

/// Escalating "space left" alert fired when a provider's gauge crosses below
/// 25 / 15 / 10 / 5 percent remaining. Each threshold fires once per window;
/// everything re-arms when the window resets (remaining climbs back up).
public struct ThresholdAlert: Sendable, Equatable {
    public var provider: ProviderID
    /// 25, 15, 10 or 5 — percent LEFT.
    public var threshold: Int
    public var remaining: Double
    public var isWeekly: Bool
    public var firedAt: Date

    public init(provider: ProviderID, threshold: Int, remaining: Double, isWeekly: Bool, firedAt: Date = Date()) {
        self.provider = provider
        self.threshold = threshold
        self.remaining = remaining
        self.isWeekly = isWeekly
        self.firedAt = firedAt
    }
}

public enum ThresholdAlerts {
    public static let levels = [25, 15, 10, 5]
    /// Re-arm only after the gauge climbs clearly above the top threshold,
    /// so jitter around a boundary can't re-fire the same alert.
    static let resetAbove: Double = 27

    /// The deepest threshold newly crossed, or nil.
    public static func newCrossing(remaining: Double, alreadyFired: Set<Int>) -> Int? {
        levels
            .filter { remaining <= Double($0) && !alreadyFired.contains($0) }
            .min()
    }

    /// All thresholds the current value sits at or below (mark them fired
    /// together so a steep drop produces one alert, not a cascade).
    public static func crossed(remaining: Double) -> Set<Int> {
        Set(levels.filter { remaining <= Double($0) })
    }

    public static func shouldReset(remaining: Double) -> Bool {
        remaining > resetAbove
    }

    public static func attentionLevel(for threshold: Int) -> AttentionLevel {
        threshold <= 10 ? .critical : .warning
    }

    public static func message(for alert: ThresholdAlert) -> String {
        let window = alert.isWeekly ? "weekly limit" : "5h session"
        return "\(alert.provider.displayName): \(Int(alert.remaining.rounded()))% of the \(window) left"
    }
}
