import XCTest
@testable import NotchAgent

final class SessionInsightsPayloadTests: XCTestCase {
    private func samplePayload() -> SessionInsightsPayload {
        SessionInsightsPayload(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            provider: .claudeCode,
            window: DateInterval(start: Date(timeIntervalSince1970: 1_799_000_000), duration: 7_200),
            aggregate: TokenUsage(input: 30_000, output: 10_000, cacheWrite: 5_000, cacheRead: 55_000),
            cacheShare: 0.55,
            tokensByTool: ["Read": TokenUsage(input: 40_000, output: 0, cacheWrite: 0, cacheRead: 30_000)],
            tokensByModel: ["claude-sonnet-5": TokenUsage(input: 95_000, output: 5_000, cacheWrite: 0, cacheRead: 0)],
            agentSplit: .init(main: TokenUsage(input: 90_000, output: 9_000, cacheWrite: 0, cacheRead: 40_000),
                              subagent: TokenUsage(input: 10_000, output: 1_000, cacheWrite: 0, cacheRead: 15_000)),
            topMessages: [.init(requestId: "req_1", timestamp: Date(timeIntervalSince1970: 1_799_500_000),
                                model: "claude-sonnet-5",
                                tokens: TokenUsage(input: 20_000, output: 2_000, cacheWrite: 0, cacheRead: 10_000),
                                toolNames: ["Read", "Bash"])],
            preview: .init(line: "Cache 55%", tier: .ok))
    }

    func testPayloadCodableRoundTripPreservesBitForBit() throws {
        let payload = samplePayload()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SessionInsightsPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testPayloadWithBurnoutNilStillRoundTrips() throws {
        var payload = samplePayload()
        payload.burnout = .init(title: "CALMA AÍ", detail: "Nesse ritmo você ficará sem token às 15:00.", exhaustsAt: nil)
        let decoded = try JSONDecoder().decode(
            SessionInsightsPayload.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(decoded.burnout?.title, "CALMA AÍ")
    }
}
