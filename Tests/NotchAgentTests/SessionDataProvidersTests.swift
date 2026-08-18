import XCTest
@testable import NotchAgent

final class SessionDataProvidersTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("insights-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func fixtureBundleURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")!
    }

    // REGRESSÃO: atribuição de subagente = arquivos "agent-*.jsonl" vs arquivos
    // principais do transcript (fonte da verdade: estrutura real de ~/.claude/projects).
    func testAgentSplitClassifiesByFilename() async throws {
        let fixtureData = try Data(contentsOf: fixtureBundleURL("claude-session-activity"))
        try fixtureData.write(to: tempRoot.appendingPathComponent("main.jsonl"))
        try fixtureData.write(to: tempRoot.appendingPathComponent("agent-abc123.jsonl"))

        let provider = ClaudeSessionDataProvider(roots: [tempRoot], lookbackHours: 6)
        let split = await provider.agentSplit(provider: .claudeCode)
        XCTAssertNotNil(split)
        // main.jsonl: 2 mensagens (1000+100 input, 200+40 output, 0+10 cacheWrite, 9000+20 cacheRead)
        XCTAssertEqual(split?.main, TokenUsage(input: 1_100, output: 240, cacheWrite: 10, cacheRead: 9_020))
        // agent-abc123.jsonl: mesmos números, no balde de subagente
        XCTAssertEqual(split?.subagent, TokenUsage(input: 1_100, output: 240, cacheWrite: 10, cacheRead: 9_020))
    }

    // REGRESSÃO: registro Codex = rollout mais novo com modelo do turn_context
    // e normalização de cached (input subtraído, cacheRead = cached).
    func testCodexRecordUsesRolloutStartAndNormalizedTotals() throws {
        let record = try CodexSessionDataProvider.record(for: fixtureBundleURL("codex-session-activity"))
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.model, "gpt-5")
        XCTAssertEqual(record?.tokens, TokenUsage(input: 300_000, output: 72_504, cacheWrite: 0, cacheRead: 100_000))
        XCTAssertEqual(record?.toolNames, [])
    }
}
