import XCTest
@testable import NotchAgent

/// CALIBRAÇÃO: os números de tokens devem se referir à MESMA janela que o
/// percentual oficial ao lado deles, e todas as fontes locais de transcript
/// (CLI + Desktop app agent mode) devem ser contadas.
final class PrecisionCalibrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("precision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func iso(_ date: Date) -> String { date.ISO8601Format() }

    private func usageLine(id: String, date: Date, input: Int, output: Int) -> String {
        """
        {"type":"assistant","timestamp":"\(iso(date))","requestId":"\(id)","message":{"id":"m_\(id)","model":"claude-fable-5","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
        """
    }

    func testSumBucketsRespectsWindowBoundaries() {
        let base = Timestamps.parseISO8601("2026-07-14T10:00:00Z")!
        var merged: [Date: ClaudeFileStat.HourStat] = [:]
        for offset in 0..<10 {
            var stat = ClaudeFileStat.HourStat()
            stat.tokens = TokenUsage(input: 100, output: 0)
            stat.costUSD = 1
            merged[base.addingTimeInterval(Double(offset) * 3600)] = stat
        }
        // Janela de 5h começando às 12:00 → buckets 12,13,14,15,16.
        let start = base.addingTimeInterval(2 * 3600)
        let end = start.addingTimeInterval(5 * 3600)
        let result = ClaudeProvider.sumBuckets(merged, from: start, to: end)
        XCTAssertEqual(result.tokens.total, 500)
        XCTAssertEqual(result.costUSD, 5, accuracy: 0.001)
    }

    func testClaudeScansMultipleRoots() async throws {
        // Root 1: CLI (~/.claude/projects). Root 2: Desktop agent mode.
        let cliRoot = root.appendingPathComponent("projects/-Users-test")
        let desktopRoot = root.appendingPathComponent("desktop/session-a/task-b")
        try FileManager.default.createDirectory(at: cliRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: desktopRoot, withIntermediateDirectories: true)

        let now = Date()
        try Data((usageLine(id: "cli", date: now.addingTimeInterval(-1800), input: 100, output: 100) + "\n").utf8)
            .write(to: cliRoot.appendingPathComponent("session.jsonl"))
        try Data((usageLine(id: "desk", date: now.addingTimeInterval(-1200), input: 50, output: 50) + "\n").utf8)
            .write(to: desktopRoot.appendingPathComponent("audit.jsonl"))

        let provider = ClaudeProvider(
            roots: [root.appendingPathComponent("projects"), root.appendingPathComponent("desktop")],
            probe: nil
        )
        let snapshot = try await provider.fetchSnapshot(settings: AppSettings())
        XCTAssertEqual(
            snapshot.weekly?.tokens.total, 300,
            "desktop agent-mode sessions must be counted alongside CLI transcripts"
        )
    }

    func testCodexSessionSumsConcurrentRolloutsInWindow() async throws {
        let dayDir = root.appendingPathComponent("sessions/2026/07/14")
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        let now = Date()
        let resets = now.addingTimeInterval(2 * 3600)
        func rollout(_ name: String, minutesAgo: Double, tokens: Int, withLimits: Bool) throws {
            let limits = withLimits
                ? """
                ,"rate_limits":{"primary":{"used_percent":30.0,"window_minutes":300,"resets_at":\(resets.timeIntervalSince1970)},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":\(resets.timeIntervalSince1970 + 86_400)},"plan_type":"pro"}
                """
                : ""
            let content = """
            {"timestamp":"\(iso(now.addingTimeInterval(-minutesAgo * 60)))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(tokens),"cached_input_tokens":0,"output_tokens":0,"total_tokens":\(tokens)}}\(limits)}}
            """
            try Data((content + "\n").utf8).write(to: dayDir.appendingPathComponent(name))
        }
        // Duas sessões dentro da janela de 5h + uma antiga fora dela.
        try rollout("rollout-a.jsonl", minutesAgo: 10, tokens: 1000, withLimits: true)
        try rollout("rollout-b.jsonl", minutesAgo: 60, tokens: 500, withLimits: false)
        try rollout("rollout-old.jsonl", minutesAgo: 400, tokens: 9999, withLimits: false)

        let provider = CodexProvider(root: root.appendingPathComponent("sessions"))
        let snapshot = try await provider.fetchSnapshot(settings: AppSettings())
        XCTAssertEqual(
            snapshot.session?.tokens.total, 1500,
            "concurrent rollouts inside the 5h window must be summed; older ones excluded"
        )
        XCTAssertEqual(snapshot.session?.usedPercent, 30.0)
    }
}
