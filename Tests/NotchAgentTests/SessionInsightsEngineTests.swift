import XCTest
@testable import NotchAgent

final class SessionInsightsEngineTests: XCTestCase {
    func testWindowFallsBackToLastActivity() {
        let now = Date()
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok,
                                    lastActivityAt: now.addingTimeInterval(-3_600))
        let window = SessionInsightsEngine.window(from: snapshot, now: now)
        XCTAssertNotNil(window)
    }

    func testRefreshWithEmptyProviderProducesNoPayloads() async {
        let now = Date()
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok,
                                    session: SessionUsage(startedAt: now.addingTimeInterval(-600)))
        let payloads = await SessionInsightsEngine.refresh(
            snapshots: [.claudeCode: snapshot], now: now)
        XCTAssertTrue(payloads.isEmpty)   // sem dados, produção não muda
    }

    func testRefreshWithFakeProviderProducesOnePayloadPerProvider() async {
        let now = Date()
        struct Fake: SessionDataProvider {
            let now: Date
            func messages(provider: ProviderID) async -> [PayloadBuilder.MessageRecord] {
                [.init(timestamp: now.addingTimeInterval(-300), requestId: "a", model: "m",
                       tokens: TokenUsage(input: 1_000, output: 100, cacheWrite: 0, cacheRead: 500), toolNames: ["Read"])]
            }
            func agentSplit(provider: ProviderID) async -> SessionInsightsPayload.AgentSplit? { nil }
        }
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok,
                                    session: SessionUsage(startedAt: now.addingTimeInterval(-600)))
        let payloads = await SessionInsightsEngine.refresh(
            snapshots: [.claudeCode: snapshot], dataProvider: Fake(now: now), now: now)
        XCTAssertEqual(payloads.count, 1)
        // 500/1600 = 31% cache, ferramenta Read 100% mas cache não fria →
        // branch de ferramenta dominante
        XCTAssertEqual(payloads[.claudeCode]?.preview.line, "Topo: Read 100%")
    }
}
