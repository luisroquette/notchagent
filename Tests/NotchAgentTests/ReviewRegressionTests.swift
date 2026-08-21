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

/// Reproduces the bug reported 15/08/2026 and its two follow-ups, found by
/// re-testing against live data after each deploy:
/// 1. `codex /status` showed "Weekly limit: 0% left" (sol, exhausted) AND
///    "GPT-5.3-Codex-Spark Weekly limit: 91% left". NotchAgent showed only
///    92% — it picked up whichever scope the newest single rollout event
///    happened to report and never recovered the other.
/// 2. First fix attempt keyed scopes by `limit_name` — null on every
///    locally-observed event, useless.
/// 3. Second fix attempt keyed scopes by `resetsAt` — NOT stable either:
///    Codex recomputes it fresh on every response, so the same model's cap
///    carries a different `resetsAt` on every sighting (sometimes 1 second
///    apart), fragmenting one real scope into dozens of fake ones and
///    surfacing arbitrary stale readings. `model` is the only field that's
///    genuinely stable, and it's what the breakdown needs anyway.
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

    // REGRESSÃO (21/08): a política mudou — Codex models are independent
    // quota pools (verified empirically: a 429 on one model, then switching
    // to another, worked immediately). "Worst model wins the headline" used
    // to be the rule; now it's "most headroom wins" (see
    // CodexProvider.primaryWeeklyScope). This test keeps its original job —
    // proving resetsAt drift on the SAME model never fragments it into two
    // scopes — but the headline assertion now points at the model WITH
    // room, not the exhausted one.
    func testBestModelIsTheHeadlineNumberEvenWhenAnOlderSighting() async throws {
        let now = Date()
        // "resetsAt drift" from the real bug: two sightings of the SAME
        // model, minutes apart, computed slightly different reset times.
        let solResetsA = now.addingTimeInterval(5 * 24 * 3600).timeIntervalSince1970
        let solResetsB = solResetsA + 1
        let sparkResets = now.addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970

        // Older rollout (hours ago): sol is exhausted.
        let solContent = """
        {"timestamp":"\(now.addingTimeInterval(-6 * 3600).ISO8601Format())","type":"turn_context","payload":{"cwd":"/Users/test","model":"gpt-5.6-sol","approval_policy":"on-request"}}
        {"timestamp":"\(now.addingTimeInterval(-6 * 3600).ISO8601Format())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":100,"total_tokens":1100}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":100.0,"window_minutes":10080,"resets_at":\(solResetsA)},"secondary":null,"plan_type":"pro"}}}
        """
        try Data((solContent + "\n").utf8).write(
            to: root.appendingPathComponent("sessions/2026/08/15/rollout-sol-old.jsonl")
        )
        // A second, slightly newer sol sighting with a DRIFTED resetsAt —
        // must collapse into the same scope, not create a second one.
        let solDriftContent = """
        {"timestamp":"\(now.addingTimeInterval(-3 * 3600).ISO8601Format())","type":"turn_context","payload":{"cwd":"/Users/test","model":"gpt-5.6-sol","approval_policy":"on-request"}}
        {"timestamp":"\(now.addingTimeInterval(-3 * 3600).ISO8601Format())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":0,"output_tokens":120,"total_tokens":1320}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":100.0,"window_minutes":10080,"resets_at":\(solResetsB)},"secondary":null,"plan_type":"pro"}}}
        """
        try Data((solDriftContent + "\n").utf8).write(
            to: root.appendingPathComponent("sessions/2026/08/15/rollout-sol-drift.jsonl")
        )

        // Newest rollout: spark still has room.
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
            snapshot.weekly?.usedPercent, 8.0,
            "the model with the MOST headroom must be the headline number — models are independent, so the exhausted one doesn't block the other"
        )
        let names = snapshot.weekly?.namedQuotas?.map(\.name).sorted() ?? []
        XCTAssertEqual(names, ["gpt-5.3-codex-spark", "gpt-5.6-sol"], "resetsAt drift must not fragment sol into two entries")
        let sol = try XCTUnwrap(snapshot.weekly?.namedQuotas?.first { $0.name == "gpt-5.6-sol" })
        XCTAssertEqual(sol.usedPercent, 100.0, "the exhausted model must still be recoverable for the detail view")
    }

    /// Reproduces the 15/08/2026 follow-up bug: the breakdown showed the
    /// same model twice, both stuck at "0% left", because scopes whose
    /// resetsAt had already passed (dead, from a previous week) were never
    /// filtered out of the named-quota list — only the headline number was
    /// protected against staleness.
    func testExpiredScopeNeverAppearsInTheBreakdown() async throws {
        let now = Date()
        let expiredResets = now.addingTimeInterval(-3600).timeIntervalSince1970 // already passed
        let liveResets = now.addingTimeInterval(6 * 24 * 3600).timeIntervalSince1970

        let expiredContent = """
        {"timestamp":"\(now.addingTimeInterval(-2 * 24 * 3600).ISO8601Format())","type":"turn_context","payload":{"cwd":"/Users/test","model":"gpt-5.6-sol","approval_policy":"on-request"}}
        {"timestamp":"\(now.addingTimeInterval(-2 * 24 * 3600).ISO8601Format())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":0,"output_tokens":50,"total_tokens":550}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":0.0,"window_minutes":10080,"resets_at":\(expiredResets)},"secondary":null,"plan_type":"pro"}}}
        """
        try Data((expiredContent + "\n").utf8).write(
            to: root.appendingPathComponent("sessions/2026/08/15/rollout-expired.jsonl")
        )

        let liveContent = """
        {"timestamp":"\(now.ISO8601Format())","type":"turn_context","payload":{"cwd":"/Users/test","model":"gpt-5.3-codex-spark","approval_policy":"on-request"}}
        {"timestamp":"\(now.ISO8601Format())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":100,"total_tokens":1100}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":40.0,"window_minutes":10080,"resets_at":\(liveResets)},"secondary":null,"plan_type":"pro"}}}
        """
        try Data((liveContent + "\n").utf8).write(
            to: root.appendingPathComponent("sessions/2026/08/15/rollout-live.jsonl")
        )

        let provider = CodexProvider(root: root.appendingPathComponent("sessions"))
        let snapshot = try await provider.fetchSnapshot(settings: AppSettings())

        let names = snapshot.weekly?.namedQuotas?.map(\.name) ?? []
        XCTAssertEqual(names, ["gpt-5.3-codex-spark"], "an expired scope must never appear in the breakdown, no matter how it reads")
        XCTAssertEqual(snapshot.weekly?.usedPercent, 40.0, "the headline must come from the live scope, not a stale one")
    }
}
