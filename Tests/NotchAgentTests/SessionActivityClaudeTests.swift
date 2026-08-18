import XCTest
@testable import NotchAgent

final class SessionActivityClaudeTests: XCTestCase {
    private func fixtureURL() -> URL {
        Bundle.module.url(forResource: "claude-session-activity", withExtension: "jsonl", subdirectory: "Fixtures")!
    }

    func testParseMessagesReturnsAssistantMessagesWithUsage() throws {
        let records = try ClaudeTranscriptParser.parseMessages(at: fixtureURL())
        XCTAssertEqual(records.count, 2)                      // linhas user sem usage são ignoradas
        XCTAssertEqual(records[0].requestId, "req_1")
        XCTAssertEqual(records[0].model, "claude-sonnet-5")
        XCTAssertEqual(records[0].tokens, TokenUsage(input: 1000, output: 200, cacheWrite: 0, cacheRead: 9000))
        XCTAssertEqual(records[0].toolNames, ["Read", "Bash"])
        XCTAssertEqual(records[1].toolNames, [])
        XCTAssertEqual(records[1].tokens.cacheWrite, 10)
    }
}
