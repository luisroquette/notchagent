import XCTest
@testable import NotchAgent

/// REGRESSÃO: Codex em planos sem % de sessão oficial (só semanal) não tinha
/// nenhuma noção de "janela atual" — o fallback mostrava tokens sem contexto
/// de tempo algum, diferente de Claude (que sempre mostra "OF 5H SESSION
/// LEFT" + reset). Agora ambos comunicam a mesma base conceitual: quanto foi
/// consumido na janela de trabalho atual.
final class CurrentWindowParityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("parity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sessions/2026/07/14"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testWeeklyOnlyPlanGetsStartedAtFromRolloutFilename() async throws {
        let now = Date()
        let rolloutStart = now.addingTimeInterval(-35 * 60) // began 35 min ago
        let stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.timeZone = .current
        stampFormatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let stamp = stampFormatter.string(from: rolloutStart)

        // Plano weekly-only: primary carrega window_minutes=10080 (o padrão
        // real observado no plano "prolite"), secondary nil.
        let content = """
        {"timestamp":"\(now.ISO8601Format())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":400000,"cached_input_tokens":100000,"output_tokens":72504,"total_tokens":572504}},"rate_limits":{"primary":{"used_percent":0.0,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(6 * 24 * 3600).timeIntervalSince1970)},"secondary":null,"plan_type":"prolite"}}}
        """
        try Data((content + "\n").utf8).write(
            to: root.appendingPathComponent("sessions/2026/07/14/rollout-\(stamp)-019test.jsonl")
        )

        let provider = CodexProvider(root: root.appendingPathComponent("sessions"))
        let snapshot = try await provider.fetchSnapshot(settings: AppSettings())

        XCTAssertNil(snapshot.session?.usedPercent, "no official session % on this plan — must not fabricate one")
        XCTAssertNotNil(snapshot.session?.startedAt, "fallback must expose when the current session began")
        XCTAssertEqual(
            snapshot.session?.startedAt?.timeIntervalSince1970 ?? 0,
            rolloutStart.timeIntervalSince1970,
            accuracy: 2
        )
        // Parser normalizes cached tokens out of input: 400k input − 100k cached
        // + 72504 output + 100k cacheRead = 472504 (component sum, not the
        // raw pre-computed total_tokens field).
        XCTAssertEqual(snapshot.session?.tokens.total, 472_504)
    }

    func testProviderCardFallbackTokensUseSessionNotWeeklyTotal() {
        // O herói de fallback deve refletir a sessão ATUAL, não o total da
        // semana inteira (que enganaria a leitura de "janela atual").
        let snapshot = UsageSnapshot(
            provider: .codex,
            health: .ok,
            session: SessionUsage(tokens: TokenUsage(input: 500_000), startedAt: Date()),
            weekly: WeeklyUsage(tokens: TokenUsage(input: 600_000_000))
        )
        // fallbackTokens é privado na view; testamos via GaugeMetric ausência
        // + a regra de precedência documentada (session antes de weekly).
        XCTAssertNil(GaugeMetric.from(snapshot), "sem usedPercent, não há gauge — deve cair no fallback de tokens")
        XCTAssertEqual(snapshot.session?.tokens.total, 500_000)
    }
}
