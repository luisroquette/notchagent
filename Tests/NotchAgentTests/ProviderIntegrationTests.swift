import XCTest
@testable import NotchAgent

/// End-to-end provider tests over synthetic data directories with *recent*
/// timestamps, exercising the full scan → parse → snapshot pipeline.
final class ProviderIntegrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchagent-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func iso(_ date: Date) -> String {
        date.ISO8601Format()
    }

    func testClaudeProviderEndToEnd() async throws {
        let projectDir = root.appendingPathComponent("projects/-Users-test", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let now = Date()
        func line(_ date: Date, id: String, input: Int, output: Int) -> String {
            """
            {"type":"assistant","timestamp":"\(iso(date))","requestId":"\(id)","message":{"id":"m_\(id)","model":"claude-fable-5","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
            """
        }
        let content = [
            line(now.addingTimeInterval(-90 * 60), id: "a", input: 100, output: 400),
            line(now.addingTimeInterval(-30 * 60), id: "b", input: 50, output: 250),
            line(now.addingTimeInterval(-3 * 86_400), id: "c", input: 1000, output: 2000),
        ].joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: projectDir.appendingPathComponent("session.jsonl"))

        var settings = AppSettings()
        settings.claudeSessionTokenBudget = 1600

        // probe: nil keeps integration tests offline and exercises the budget fallback.
        let provider = ClaudeProvider(root: root.appendingPathComponent("projects"), probe: nil)
        let snapshot = try await provider.fetchSnapshot(settings: settings)

        XCTAssertEqual(snapshot.health, .ok)
        let session = try XCTUnwrap(snapshot.session)
        XCTAssertEqual(session.tokens.total, 800, "current 5h block should include only recent activity")
        XCTAssertEqual(session.usedPercent.map { Int($0) }, 50)
        XCTAssertNotNil(session.resetsAt)

        let weekly = try XCTUnwrap(snapshot.weekly)
        XCTAssertEqual(weekly.tokens.total, 3800)
        XCTAssertEqual(snapshot.activeModel, "claude-fable-5")
        XCTAssertFalse(weekly.dailyTotals.isEmpty)
        XCTAssertFalse(weekly.hourlyTotals?.isEmpty ?? true, "hourly rhythm data must be populated")
    }

    func testClaudeProviderNotInstalled() async throws {
        let provider = ClaudeProvider(root: root.appendingPathComponent("missing"), probe: nil)
        let snapshot = try await provider.fetchSnapshot(settings: AppSettings())
        XCTAssertEqual(snapshot.health, .notInstalled)
    }

    func testCodexProviderEndToEnd() async throws {
        let dayDir = root.appendingPathComponent("sessions/2026/07/13", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        let now = Date()
        let resetPrimary = now.addingTimeInterval(2 * 3600).timeIntervalSince1970
        let content = """
        {"timestamp":"\(iso(now.addingTimeInterval(-700)))","type":"turn_context","payload":{"model":"gpt-5.2-codex"}}
        {"timestamp":"\(iso(now.addingTimeInterval(-600)))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"cached_input_tokens":500,"output_tokens":300,"total_tokens":2300}},"rate_limits":{"primary":{"used_percent":42.0,"window_minutes":300,"resets_at":\(resetPrimary)},"secondary":{"used_percent":63.0,"window_minutes":10080,"resets_at":\(resetPrimary + 86_400)},"plan_type":"pro"}}}
        """
        try Data(content.utf8).write(to: dayDir.appendingPathComponent("rollout-test.jsonl"))

        let provider = CodexProvider(root: root.appendingPathComponent("sessions"))
        let snapshot = try await provider.fetchSnapshot(settings: AppSettings())

        XCTAssertEqual(snapshot.health, .ok)
        XCTAssertEqual(snapshot.session?.usedPercent, 42.0)
        XCTAssertEqual(snapshot.weekly?.usedPercent, 63.0)
        XCTAssertEqual(snapshot.session?.tokens.total, 1500 + 500 + 300)
        XCTAssertEqual(snapshot.note, "Plan: pro")
        XCTAssertNotNil(snapshot.session?.resetsAt)
        XCTAssertEqual(snapshot.activeModel, "gpt-5.2-codex")
        XCTAssertEqual(snapshot.modelBreakdown?.first?.model, "gpt-5.2-codex")
        XCTAssertEqual(snapshot.modelBreakdown?.first?.tokens, 2300)
    }

    func testGeminiProviderPartialSupport() async throws {
        let projectTmp = root.appendingPathComponent("tmp/abc123", isDirectory: true)
        try FileManager.default.createDirectory(at: projectTmp, withIntermediateDirectories: true)
        let now = Date()
        let content = """
        [{"sessionId":"s1","messageId":0,"type":"user","message":"hi","timestamp":"\(iso(now.addingTimeInterval(-3600)))"}]
        """
        try Data(content.utf8).write(to: projectTmp.appendingPathComponent("logs.json"))

        let provider = GeminiProvider(root: root)
        let snapshot = try await provider.fetchSnapshot(settings: AppSettings())

        XCTAssertEqual(snapshot.health, .ok)
        XCTAssertNil(snapshot.session, "gemini must not fabricate token data")
        XCTAssertNil(snapshot.weekly)
        XCTAssertNotNil(snapshot.lastActivityAt)
        XCTAssertTrue(snapshot.note?.contains("1 prompts today") ?? false)
    }
}
