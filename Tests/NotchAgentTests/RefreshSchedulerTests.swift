import XCTest
@testable import NotchAgent

final class RefreshSchedulerTests: XCTestCase {
    func testForcedRefreshDuringInFlightRefreshIsQueued() {
        var queue = RefreshRequestQueue()

        XCTAssertTrue(queue.begin(force: false))
        XCTAssertFalse(queue.begin(force: true))
        XCTAssertTrue(queue.finish())

        XCTAssertTrue(queue.begin(force: true))
        XCTAssertFalse(queue.finish())
    }

    func testRepeatedForcedClicksCoalesceIntoOneFollowUpRefresh() {
        var queue = RefreshRequestQueue()

        XCTAssertTrue(queue.begin(force: true))
        XCTAssertFalse(queue.begin(force: true))
        XCTAssertFalse(queue.begin(force: true))
        XCTAssertTrue(queue.finish())

        XCTAssertTrue(queue.begin(force: true))
        XCTAssertFalse(queue.finish())
    }

    func testNewerProviderGenerationRejectsOlderResponse() {
        var tracker = RefreshGenerationTracker()
        let older = tracker.beginProvider(.apiAccounts)
        let newer = tracker.beginProvider(.apiAccounts)

        XCTAssertFalse(tracker.acceptsProvider(.apiAccounts, generation: older))
        XCTAssertTrue(tracker.acceptsProvider(.apiAccounts, generation: newer))
    }

    func testIndividualRefreshProtectsOnlyItsAccountFromOlderGlobalResponse() {
        var tracker = RefreshGenerationTracker()
        let first = UUID()
        let second = UUID()
        let global = tracker.beginProvider(.apiAccounts)
        let individual = tracker.beginAccount(first)

        XCTAssertTrue(tracker.acceptsProvider(.apiAccounts, generation: global))
        XCTAssertTrue(tracker.accountIsNewer(first, than: global))
        XCTAssertFalse(tracker.accountIsNewer(second, than: global))

        tracker.didApplyProvider(
            .apiAccounts,
            generation: global,
            accountIDs: [first, second]
        )
        XCTAssertTrue(tracker.acceptsAccount(first, generation: individual))
    }

    @MainActor
    func testAccountRefreshStateBecomesStaleAfterThreshold() {
        let suite = "RefreshSchedulerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(preferences: PreferencesStore(defaults: defaults))
        let accountID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        store.apply(UsageSnapshot(
            provider: .apiAccounts,
            capturedAt: capturedAt,
            health: .ok,
            accountUsage: [
                APIAccountUsage(
                    accountID: accountID,
                    label: "Conta",
                    service: .openAI,
                    capturedAt: capturedAt,
                    usedPercent: nil,
                    resetsAt: nil,
                    summary: "Atualizado",
                    readStatus: .updated
                ),
            ]
        ))

        XCTAssertEqual(
            store.accountRefreshState(
                accountID,
                now: capturedAt.addingTimeInterval(1_201),
                staleAfter: 1_200
            ),
            .stale(capturedAt)
        )
    }

    func testInvalidatedAccountCacheRejectsLateStore() async {
        let cache = APIAccountSnapshotCache()
        let oldRevision = await cache.currentRevision()
        let old = UsageSnapshot(provider: .apiAccounts, health: .ok, note: "old")

        await cache.clear()
        await cache.store(old, fingerprint: "same", ifRevision: oldRevision)

        let leaked = await cache.fresh(fingerprint: "same")
        XCTAssertNil(leaked)

        let currentRevision = await cache.currentRevision()
        let fresh = UsageSnapshot(provider: .apiAccounts, health: .ok, note: "fresh")
        await cache.store(fresh, fingerprint: "same", ifRevision: currentRevision)
        let restored = await cache.fresh(fingerprint: "same")
        XCTAssertEqual(restored?.note, "fresh")
    }
}
