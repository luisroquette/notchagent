import XCTest
@testable import NotchAgent

final class CostLayersTests: XCTestCase {
    func testAggregatesOnlyProviderWeeklyEstimates() {
        let claude = UsageSnapshot(provider: .claudeCode, health: .ok, weekly: WeeklyUsage(cost: CostEstimate(amountUSD: 12.5)))
        let codex = UsageSnapshot(provider: .codex, health: .ok, weekly: WeeklyUsage(cost: CostEstimate(amountUSD: 7.5)))
        let gemini = UsageSnapshot(provider: .geminiCLI, health: .noData)

        let layers = EstimatedCostLayers.fromSnapshots([.claudeCode: claude, .codex: codex, .geminiCLI: gemini])

        XCTAssertEqual(layers.totalUSD, 20)
        XCTAssertEqual(layers.byProvider[.claudeCode], 12.5)
        XCTAssertNil(layers.byProvider[.geminiCLI])
    }
}
