import XCTest
import AgentMeterCore
@testable import NotchAgent

final class DecisionAdvisorTests: XCTestCase {
    func testCriticalBudgetRecommendsReducingCost() {
        let summary = MonthlySpendSummary(history: [], expenses: [AIExpense(provider: .claude, title: "Invoice", amountBRL: 95, kind: .apiUsage, source: .officialInvoice)], subscriptions: [])
        let budget = MonthlyBudgetStatus(summary: summary, budgetBRL: 100)
        let advice = DecisionAdvisor.advise(snapshots: [:], budget: budget)
        XCTAssertEqual(advice.first?.severity, .critical)
        XCTAssertTrue(advice.first?.title.contains("Reduza") == true)
    }

    func testLowQuotaIsFlagged() {
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok, session: SessionUsage(usedPercent: 85))
        let advice = DecisionAdvisor.advise(snapshots: [.claudeCode: snapshot], budget: nil)
        XCTAssertTrue(advice.contains { $0.title.contains("Poupe Claude") })
    }
}
