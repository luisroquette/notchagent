import XCTest
@testable import NotchAgent

final class CodexParserTests: XCTestCase {
    private var fixtureURL: URL {
        Bundle.module.url(forResource: "codex-rollout", withExtension: "jsonl", subdirectory: "Fixtures")!
    }

    func testPicksLatestTokenCountEvent() throws {
        let info = try XCTUnwrap(CodexRolloutParser.latestTokenInfo(at: fixtureURL))
        XCTAssertEqual(info.primary?.usedPercent, 10.0)
        XCTAssertEqual(info.secondary?.usedPercent, 19.0)
        XCTAssertEqual(info.planType, "prolite")
    }

    func testNormalizesCachedInputTokens() throws {
        let info = try XCTUnwrap(CodexRolloutParser.latestTokenInfo(at: fixtureURL))
        // input 16621 with 4480 cached → 12141 fresh input + 4480 cache reads.
        XCTAssertEqual(info.totals.input, 12141)
        XCTAssertEqual(info.totals.cacheRead, 4480)
        XCTAssertEqual(info.totals.output, 398)
        XCTAssertEqual(info.totals.total, 12141 + 4480 + 398)
    }

    func testParsesResetTimestamps() throws {
        let info = try XCTUnwrap(CodexRolloutParser.latestTokenInfo(at: fixtureURL))
        XCTAssertEqual(info.primary?.resetsAt, Date(timeIntervalSince1970: 1_782_408_090))
        XCTAssertEqual(info.secondary?.resetsAt, Date(timeIntervalSince1970: 1_782_591_969))
        XCTAssertEqual(info.primary?.windowMinutes, 300)
        XCTAssertEqual(info.secondary?.windowMinutes, 10080)
    }

    func testExtractsModelFromTurnContext() throws {
        let info = try XCTUnwrap(CodexRolloutParser.latestTokenInfo(at: fixtureURL))
        XCTAssertEqual(info.model, "gpt-5.1-codex")
    }

    func testFileWithoutTokenCountReturnsNil() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).jsonl")
        try Data("{\"type\":\"session_meta\",\"payload\":{}}\n".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertNil(try CodexRolloutParser.latestTokenInfo(at: tmp))
    }
}

final class GeminiParserTests: XCTestCase {
    private var fixtureURL: URL {
        Bundle.module.url(forResource: "gemini-logs", withExtension: "json", subdirectory: "Fixtures")!
    }

    func testCountsPromptsAndSessions() throws {
        let stat = try GeminiLogParser.parseLogFile(at: fixtureURL)
        XCTAssertEqual(stat.promptTimestamps.count, 3)
        XCTAssertEqual(stat.sessionIDs, ["s1", "s2"])
        XCTAssertEqual(stat.lastActivity, Timestamps.parseISO8601("2026-07-11T09:00:00.000Z"))
    }
}

// MARK: - Session percent estimate (5h budget fallback)

final class CodexSessionBudgetTests: XCTestCase {
    func testEstimatedSessionPercentNilWithoutBudget() {
        XCTAssertNil(CodexProvider.estimatedSessionPercent(tokens: 1_000, budget: nil))
        XCTAssertNil(CodexProvider.estimatedSessionPercent(tokens: 1_000, budget: 0))
    }

    func testEstimatedSessionPercentBasics() {
        XCTAssertEqual(CodexProvider.estimatedSessionPercent(tokens: 250, budget: 1_000), 25)
        XCTAssertEqual(CodexProvider.estimatedSessionPercent(tokens: 2_000, budget: 1_000), 100)
    }

    func testEstimatedSessionPercentZeroTokens() {
        XCTAssertEqual(CodexProvider.estimatedSessionPercent(tokens: 0, budget: 1_000), 0)
    }
}

// MARK: - Default session budget

final class CodexBudgetDefaultTests: XCTestCase {
    func testDefaultSessionBudgetWhenKeyAbsent() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.codexSessionTokenBudget, 5_000_000_000)
    }

    func testExplicitBudgetWinsOverDefault() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"codexSessionTokenBudget": 12345}"#.utf8)
        )
        XCTAssertEqual(settings.codexSessionTokenBudget, 12_345)
    }
}
