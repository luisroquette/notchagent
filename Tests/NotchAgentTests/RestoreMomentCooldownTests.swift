import XCTest
@testable import NotchAgent

/// REGRESSÃO (22/08): Codex's weekly cap stopped being permanently exhausted
/// after CodexProvider.primaryWeeklyScope started picking the model with the
/// MOST headroom instead of the least (21/08 fix) — before that, Codex's
/// GaugeMetric.isWeekly was ALWAYS true (the worst model's weekly cap always
/// won). Now it can legitimately flip true/false refresh to refresh (weekly
/// headroom vs session headline). Each flip mints a "new" fired-thresholds
/// key (`firedThresholds` is keyed per provider+window on purpose — see the
/// comment on that property), and the OTHER key's stale "fired" state looks
/// like a fresh reset on the next flip back — presentRestore fires on every
/// alternation, force-expanding the panel and celebrating "full tank" every
/// few minutes with no real quota reset. A cooldown per provider is the fix:
/// aditive, doesn't touch the intentional per-window key design.
@MainActor
final class RestoreMomentCooldownTests: XCTestCase {
    private func makeStore() -> UsageStore {
        UsageStore(preferences: PreferencesStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!))
    }

    private func snapshot(
        weeklyUsedPercent: Double?,
        sessionUsedPercent: Double?,
        lastActivityAt: Date,
        capturedAt: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            capturedAt: capturedAt,
            health: .ok,
            session: sessionUsedPercent.map { SessionUsage(usedPercent: $0) },
            weekly: weeklyUsedPercent.map { WeeklyUsage(usedPercent: $0) },
            lastActivityAt: lastActivityAt
        )
    }

    func testAlternatingWeeklySessionHeadlineDoesNotRepeatCelebrationWithinCooldown() {
        let store = makeStore()
        let base = Date()
        let now = { base.addingTimeInterval($0) }

        // 1. Weekly low (fires the "wk" key).
        store.apply(snapshot(weeklyUsedPercent: 95, sessionUsedPercent: nil, lastActivityAt: base, capturedAt: now(0)))
        // 2. Session low (fires the "5h" key — a DIFFERENT key, first observation, no restore yet).
        store.apply(snapshot(weeklyUsedPercent: nil, sessionUsedPercent: 95, lastActivityAt: base, capturedAt: now(1)))
        // 3. Weekly recovers → "wk" key had fired → celebrates.
        store.apply(snapshot(weeklyUsedPercent: 2, sessionUsedPercent: nil, lastActivityAt: base, capturedAt: now(2)))
        XCTAssertNotNil(store.activeRestoreMoment, "first recovery must celebrate")
        store.dismissRestoreMoment()

        // 4. Session recovers moments later → "5h" key had fired too → WITHOUT
        //    the cooldown this fires a second celebration seconds after the first,
        //    for the same provider, with no real reset in between.
        store.apply(snapshot(weeklyUsedPercent: nil, sessionUsedPercent: 3, lastActivityAt: base, capturedAt: now(3)))
        XCTAssertNil(
            store.activeRestoreMoment,
            "same-provider celebration within the cooldown window must be suppressed — this is the alternating-window false-positive loop, not a real reset"
        )
    }

    func testCelebrationFiresAgainAfterCooldownElapses() {
        let store = makeStore()
        let base = Date()
        let now = { base.addingTimeInterval($0) }

        store.apply(snapshot(weeklyUsedPercent: 95, sessionUsedPercent: nil, lastActivityAt: base, capturedAt: now(0)))
        store.apply(snapshot(weeklyUsedPercent: 2, sessionUsedPercent: nil, lastActivityAt: base, capturedAt: now(1)))
        XCTAssertNotNil(store.activeRestoreMoment)
        store.dismissRestoreMoment()

        // A real recovery well after the cooldown (21 min later) must still celebrate.
        let later = base.addingTimeInterval(21 * 60)
        store.apply(snapshot(weeklyUsedPercent: 95, sessionUsedPercent: nil, lastActivityAt: later, capturedAt: later))
        store.apply(snapshot(weeklyUsedPercent: 2, sessionUsedPercent: nil, lastActivityAt: later, capturedAt: later.addingTimeInterval(1)))
        XCTAssertNotNil(store.activeRestoreMoment, "a genuine recovery after the cooldown must not be silenced forever")
    }
}
