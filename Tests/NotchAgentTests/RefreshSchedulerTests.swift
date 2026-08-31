import XCTest
@testable import NotchAgent

final class RefreshSchedulerTests: XCTestCase {
    private struct SlowInsightsProvider: SessionDataProvider {
        func messages(provider: ProviderID) async -> [PayloadBuilder.MessageRecord] {
            try? await Task.sleep(for: .seconds(30))
            return []
        }

        func agentSplit(provider: ProviderID) async -> SessionInsightsPayload.AgentSplit? { nil }
    }

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

    // REGRESSÃO (31/08): insights lentos rodavam dentro de tick(), mantendo
    // RefreshRequestQueue.isRunning=true e congelando todos os providers.
    @MainActor
    func testSlowInsightsStartOutsideRefreshCriticalPath() async {
        let suite = "RefreshSchedulerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("scheduler-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let scheduler = RefreshScheduler(
            providers: [],
            store: UsageStore(preferences: PreferencesStore(defaults: defaults)),
            snapshotStore: SnapshotStore(fileURL: temp.appendingPathComponent("snapshots.json")),
            historyStore: HistoryStore(fileURL: temp.appendingPathComponent("history.json")),
            sessionDataProvider: SlowInsightsProvider()
        )
        let snapshot = UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: SessionUsage(startedAt: .now.addingTimeInterval(-60))
        )

        let clock = ContinuousClock()
        let started = clock.now
        scheduler.scheduleInsightsRefresh(snapshots: [.claudeCode: snapshot], burnout: [:])
        XCTAssertLessThan(started.duration(to: clock.now), .milliseconds(100))
        scheduler.stop()
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

    // REGRESSÃO (25/08): app.log real mostrou 156/169 falhas de Keychain com
    // status -25320 ("In dark wake, no UI possible") — o loop de tick rodava
    // a cada 60s mesmo com o Mac dormindo (Power Nap/dark wake ainda executa
    // código em background, sem poder mostrar UI). SleepGate deve bloquear
    // ticks não-forçados nesse intervalo.
    func testSleepGateBlocksTicksBetweenSleepAndWake() {
        var gate = SleepGate()
        XCTAssertFalse(gate.isAsleep, "não deve começar dormindo")

        gate.willSleep()
        XCTAssertTrue(gate.isAsleep, "willSleep deve marcar como dormindo")

        gate.didWake()
        XCTAssertFalse(gate.isAsleep, "didWake deve limpar o estado de dormindo")
    }

    func testSleepGateIgnoresRedundantTransitions() {
        var gate = SleepGate()
        gate.didWake() // nunca dormiu — não deve quebrar
        XCTAssertFalse(gate.isAsleep)

        gate.willSleep()
        gate.willSleep() // dark wake pode chamar willSleep de novo sem um wake real no meio
        XCTAssertTrue(gate.isAsleep)
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
