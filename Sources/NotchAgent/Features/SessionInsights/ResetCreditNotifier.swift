import Foundation

/// Dispatch for `ResetCreditAlerter`'s signal — same cooldown-gated shape as
/// `BurnoutNotifier`, on its own 24h cadence since expiry is measured in days.
enum ResetCreditNotifier {
    static let cooldown: TimeInterval = 24 * 3600
    static let lastNotifiedKey = "resetCredit.lastNotified.codex"

    static func shouldFire(lastNotifiedAt: Date?, now: Date = Date(), cooldown: TimeInterval = Self.cooldown) -> Bool {
        guard let lastNotifiedAt else { return true }
        return now.timeIntervalSince(lastNotifiedAt) >= cooldown
    }

    /// Returns `now` (fired) when the cooldown allows; nil when blocked.
    static func evaluate(
        signal: ResetCreditAlerter.Signal,
        gate: any NotificationGate,
        lastNotifiedAt: Date?,
        now: Date = Date()
    ) -> Date? {
        guard shouldFire(lastNotifiedAt: lastNotifiedAt, now: now) else { return nil }
        gate.post(title: signal.title, body: signal.detail)
        return now
    }
}
