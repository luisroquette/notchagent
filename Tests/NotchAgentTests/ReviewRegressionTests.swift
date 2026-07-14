import XCTest
@testable import NotchAgent

/// REGRESSÕES da revisão e2e (3 revisores independentes).
@MainActor
final class ThresholdLifecycleTests: XCTestCase {
    private func makeStore() -> UsageStore {
        UsageStore(preferences: PreferencesStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!))
    }

    private func snapshot(_ provider: ProviderID, sessionUsed: Double?, weeklyUsed: Double? = nil) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            health: .ok,
            session: sessionUsed.map { SessionUsage(usedPercent: $0) },
            weekly: weeklyUsed.map { WeeklyUsage(usedPercent: $0) },
            lastActivityAt: Date()
        )
    }

    func testStickyAlertNotReplacedByMilderCrossing() {
        let store = makeStore()
        // Codex atinge 4% restantes (sticky 5%)…
        store.apply(snapshot(.codex, sessionUsed: 96))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 5)
        // …e Claude cruza 25% no mesmo ciclo: o takeover de 5% permanece.
        store.apply(snapshot(.claudeCode, sessionUsed: 76))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 5)
        XCTAssertEqual(store.activeThresholdAlert?.provider, .codex)
    }

    func testDeeperCrossingReplacesMilderAlert() {
        let store = makeStore()
        store.apply(snapshot(.claudeCode, sessionUsed: 76))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 25)
        store.apply(snapshot(.codex, sessionUsed: 92))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 10)
    }

    func testSessionAndWeeklyWindowsHaveIndependentFiredSets() {
        let store = makeStore()
        // Sessão dispara 25%…
        store.apply(snapshot(.claudeCode, sessionUsed: 80))
        let alertsAfterSession = store.events.filter { $0.kind == .alert && $0.message.contains("left") }.count
        XCTAssertEqual(alertsAfterSession, 1)
        // …sessão fica idle e o gauge flipa para o semanal a 12% restantes:
        // o disparo da sessão não pode suprimir o alerta semanal.
        store.apply(snapshot(.claudeCode, sessionUsed: nil, weeklyUsed: 88))
        let alertsAfterWeekly = store.events.filter { $0.kind == .alert && $0.message.contains("left") }.count
        XCTAssertEqual(alertsAfterWeekly, 2, "weekly window must fire independently")
    }

    func testTransientSnapshotWithoutGaugeKeepsFiredState() {
        let store = makeStore()
        store.apply(snapshot(.claudeCode, sessionUsed: 80))
        XCTAssertEqual(store.events.filter { $0.kind == .alert && $0.message.contains("left") }.count, 1)
        // Snapshot transitório sem percentual algum (probe momentaneamente sem cache).
        store.apply(snapshot(.claudeCode, sessionUsed: nil, weeklyUsed: nil))
        // Mesmo crossing de novo → não re-dispara.
        store.apply(snapshot(.claudeCode, sessionUsed: 81))
        XCTAssertEqual(
            store.events.filter { $0.kind == .alert && $0.message.contains("left") }.count, 1,
            "transient gauge loss must not re-arm already-fired thresholds"
        )
    }

    func testAutoDismissSurvivesViewLifecycle() async throws {
        // O auto-dismiss vive no store — nenhuma view precisa existir.
        let store = makeStore()
        store.apply(snapshot(.claudeCode, sessionUsed: 76))
        XCTAssertNotNil(store.activeThresholdAlert)
        try await Task.sleep(for: .seconds(5.2))
        XCTAssertNil(store.activeThresholdAlert, "ghost alert: auto-dismiss must not depend on the view")
    }

    func testWindowResetClearsActiveAlert() {
        let store = makeStore()
        store.apply(snapshot(.claudeCode, sessionUsed: 96))
        XCTAssertNotNil(store.activeThresholdAlert)
        // Janela reseta: 5% usado → 95% restantes.
        store.apply(snapshot(.claudeCode, sessionUsed: 5))
        XCTAssertNil(store.activeThresholdAlert)
        // E os thresholds rearmam: novo crossing dispara de novo.
        store.apply(snapshot(.claudeCode, sessionUsed: 80))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 25)
    }
}

final class StaleWindowTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sessions/2026/07/10"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCodexExpiredWindowIsNotTrusted() async throws {
        // Rollout de sexta-feira: 80% usado, reset que JÁ PASSOU.
        let now = Date()
        let staleResets = now.addingTimeInterval(-2 * 24 * 3600).timeIntervalSince1970
        let content = """
        {"timestamp":"\(now.addingTimeInterval(-2 * 24 * 3600 - 600).ISO8601Format())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5000,"cached_input_tokens":0,"output_tokens":100,"total_tokens":5100}},"rate_limits":{"primary":{"used_percent":80.0,"window_minutes":300,"resets_at":\(staleResets)},"secondary":{"used_percent":70.0,"window_minutes":10080,"resets_at":\(staleResets + 3600)},"plan_type":"pro"}}}
        """
        try Data((content + "\n").utf8).write(
            to: root.appendingPathComponent("sessions/2026/07/10/rollout-old.jsonl")
        )

        let provider = CodexProvider(root: root.appendingPathComponent("sessions"))
        let snapshot = try await provider.fetchSnapshot(settings: AppSettings())
        XCTAssertNil(
            snapshot.session?.usedPercent,
            "an expired window must never present Friday's 80% as today's truth"
        )
        XCTAssertNil(snapshot.weekly?.usedPercent)
    }
}
