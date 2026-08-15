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
        store.apply(snapshot(.claudeCode, sessionUsed: 10))
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
        store.apply(snapshot(.claudeCode, sessionUsed: 10))
        store.apply(snapshot(.claudeCode, sessionUsed: 76))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 25)
        store.apply(snapshot(.codex, sessionUsed: 10))
        store.apply(snapshot(.codex, sessionUsed: 96))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 5)
    }

    func testSessionAndWeeklyWindowsHaveIndependentFiredSets() {
        let store = makeStore()
        // Sessão dispara 25%…
        store.apply(snapshot(.claudeCode, sessionUsed: 10))
        store.apply(snapshot(.claudeCode, sessionUsed: 80))
        let alertsAfterSession = store.events.filter { $0.kind == .alert && $0.message.contains("left") }.count
        XCTAssertEqual(alertsAfterSession, 1)
        // …sessão fica idle e o gauge flipa para o semanal a 12% restantes:
        // o disparo da sessão não pode suprimir o alerta semanal.
        store.apply(snapshot(.claudeCode, sessionUsed: nil, weeklyUsed: 10))
        store.apply(snapshot(.claudeCode, sessionUsed: nil, weeklyUsed: 88))
        let alertsAfterWeekly = store.events.filter { $0.kind == .alert && $0.message.contains("left") }.count
        XCTAssertEqual(alertsAfterWeekly, 2, "weekly window must fire independently")
    }

    func testTransientSnapshotWithoutGaugeKeepsFiredState() {
        let store = makeStore()
        store.apply(snapshot(.claudeCode, sessionUsed: 10))
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
        store.apply(snapshot(.claudeCode, sessionUsed: 10))
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
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 100, "reset announces the new full window")
        // E os thresholds rearmam: novo crossing dispara de novo.
        store.apply(snapshot(.claudeCode, sessionUsed: 80))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 25)
    }

    func testResetTimestampJitterDoesNotRefireThreshold() {
        let store = makeStore()
        let reset = Date().addingTimeInterval(3_600)
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: SessionUsage(resetsAt: reset, usedPercent: 10),
            lastActivityAt: Date()
        ))
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: SessionUsage(resetsAt: reset, usedPercent: 76),
            lastActivityAt: Date()
        ))
        let count = store.events.filter { $0.kind == .alert && $0.message.contains("left") }.count
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: SessionUsage(resetsAt: reset.addingTimeInterval(30), usedPercent: 77),
            lastActivityAt: Date()
        ))
        XCTAssertEqual(
            store.events.filter { $0.kind == .alert && $0.message.contains("left") }.count,
            count
        )
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

/// Reproduces the bug reported 15/08/2026: `codex /status` showed the
/// account-wide "Weekly limit" at 0% left (exhausted) AND a separate
/// "GPT-5.3-Codex-Spark Weekly limit" at 91% left. NotchAgent showed only
/// 92% left — it had picked up one scope from the newest single rollout
/// event and never recovered the (older, but still current) other scope,
/// which was actually exhausted. A first fix attempt tried to key the two
/// scopes by `limit_name`, which turned out to be null on every
/// locally-observed event for BOTH scopes (verified against live data) —
/// only `resetsAt` actually distinguishes them, so the headline number is
/// now always whichever known scope has the least headroom, regardless of
/// any label.
final class CodexNamedWeeklyQuotaTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("named-quota-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sessions/2026/08/15"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAggregateWeeklyLimitIsTheHeadlineNumberEvenWhenAnOlderSighting() async throws {
        let now = Date()
        let aggregateResets = now.addingTimeInterval(5 * 24 * 3600).timeIntervalSince1970
        let sparkResets = now.addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970

        // Older rollout (hours ago): the account-wide aggregate is exhausted.
        let aggregateContent = """
        {"timestamp":"\(now.addingTimeInterval(-6 * 3600).ISO8601Format())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":100,"total_tokens":1100}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":100.0,"window_minutes":10080,"resets_at":\(aggregateResets)},"secondary":null,"plan_type":"pro"}}}
        """
        try Data((aggregateContent + "\n").utf8).write(
            to: root.appendingPathComponent("sessions/2026/08/15/rollout-aggregate-old.jsonl")
        )

        // Newest rollout: only the OTHER (near-empty) scope was reported —
        // this is what the old code latched onto as "the" weekly number,
        // via a model with its own separate weekly cap.
        let sparkContent = """
        {"timestamp":"\(now.ISO8601Format())","type":"turn_context","payload":{"cwd":"/Users/test","model":"gpt-5.3-codex-spark","approval_policy":"on-request"}}
        {"timestamp":"\(now.ISO8601Format())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"cached_input_tokens":0,"output_tokens":200,"total_tokens":2200}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":8.0,"window_minutes":10080,"resets_at":\(sparkResets)},"secondary":null,"plan_type":"pro"}}}
        """
        try Data((sparkContent + "\n").utf8).write(
            to: root.appendingPathComponent("sessions/2026/08/15/rollout-spark-fresh.jsonl")
        )

        let provider = CodexProvider(root: root.appendingPathComponent("sessions"))
        let snapshot = try await provider.fetchSnapshot(settings: AppSettings())

        XCTAssertEqual(
            snapshot.weekly?.usedPercent, 100.0,
            "the scope with the least headroom must be the headline number, not whichever scope the newest single rollout happened to report"
        )
        let spark = try XCTUnwrap(snapshot.weekly?.namedQuotas?.first { $0.name == "gpt-5.3-codex-spark" })
        XCTAssertEqual(spark.usedPercent, 8.0, "the other scope must still be recoverable for the detail view")
    }
}
