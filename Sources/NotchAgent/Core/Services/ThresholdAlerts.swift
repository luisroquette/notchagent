import Foundation

/// Escalating "space left" alert fired when a provider's gauge crosses below
/// Configurable percent-remaining milestones. Each threshold fires once per window;
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
    public static let defaultLevels = [100, 75, 50, 25, 5]
    public static let resetBoundaryTolerance: TimeInterval = 120

    public static func normalized(_ levels: [Int]) -> [Int] {
        Array(Set(levels.map { min(100, max(1, $0)) })).sorted(by: >)
    }

    /// The deepest threshold newly crossed, or nil.
    public static func newCrossing(
        remaining: Double,
        alreadyFired: Set<Int>,
        levels: [Int] = defaultLevels
    ) -> Int? {
        normalized(levels)
            .filter { remaining <= Double($0) && !alreadyFired.contains($0) }
            .min()
    }

    /// All thresholds the current value sits at or below (mark them fired
    /// together so a steep drop produces one alert, not a cascade).
    public static func crossed(remaining: Double, levels: [Int] = defaultLevels) -> Set<Int> {
        Set(normalized(levels).filter { remaining <= Double($0) })
    }

    /// Cold start is not a crossing. Only announce a genuinely full window or
    /// an already-critical window; seed intermediate milestones silently.
    public static func initialCrossing(
        remaining: Double,
        levels: [Int] = defaultLevels
    ) -> Int? {
        let levels = normalized(levels)
        guard !levels.isEmpty else { return nil }
        if remaining >= 99.5, levels.contains(100) { return 100 }
        guard let deepest = levels.min(), remaining <= Double(deepest) else { return nil }
        return deepest
    }

    /// REGRESSÃO (22/08): the bare `remaining >= 99.5` clause used to apply
    /// even when a `previousLow` was already known, so a provider PARKED at
    /// ~100% (no real climb since the last observation — Codex's estimated
    /// session, which reports no `resetsAt`) looked like a fresh reset on
    /// every single refresh. Confirmed live: 5+ identical threshold-100
    /// alerts firing ~30s apart with the gauge never moving. Once a
    /// `previousLow` exists, only an actual climb of ≥20 points counts as a
    /// reset — sitting at the ceiling is not a climb. The bare `>= 99.5`
    /// check now only applies via the guard branch, when there is no prior
    /// observation to compare against at all.
    public static func shouldReset(remaining: Double, previousLow: Double?) -> Bool {
        guard let previousLow else { return remaining >= 99.5 }
        return remaining - previousLow >= 20
    }

    public static func resetBoundaryChanged(previous: Date?, current: Date?) -> Bool {
        guard let previous, let current else { return false }
        return abs(current.timeIntervalSince(previous)) > resetBoundaryTolerance
    }

    public static func attentionLevel(for threshold: Int) -> AttentionLevel {
        threshold <= 5 ? .critical : threshold <= 25 ? .warning : .normal
    }

    public static func message(for alert: ThresholdAlert) -> String {
        let window = alert.isWeekly ? "weekly limit" : "5h session"
        return "\(alert.provider.displayName): \(Int(alert.remaining.rounded()))% of the \(window) left"
    }
}

/// The positive counterpart to a low-fuel alert: fired once whenever a
/// provider that had crossed into low-fuel territory (any of the 25/15/10/5
/// thresholds) climbs back above the reset line — a session/weekly window
/// resetting on schedule, credits topping up, or an API block clearing all
/// look the same from here: you were worried, now you're not.
public struct RestoreMoment: Sendable, Equatable {
    public var provider: ProviderID
    /// How low it got — the animation's starting point (tank refilling from here).
    public var previousRemaining: Double
    /// Where it landed — the animation's destination.
    public var remaining: Double
    public var isWeekly: Bool
    public var firedAt: Date

    public init(
        provider: ProviderID,
        previousRemaining: Double,
        remaining: Double,
        isWeekly: Bool,
        firedAt: Date = Date()
    ) {
        self.provider = provider
        self.previousRemaining = previousRemaining
        self.remaining = remaining
        self.isWeekly = isWeekly
        self.firedAt = firedAt
    }

    public var message: String {
        let window = isWeekly ? "weekly limit" : "5h session"
        return "\(provider.displayName) is back — \(Int(remaining.rounded()))% of the \(window) left"
    }
}
