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

    // REGRESSÃO: sessão com cache frio (share < 25%) deve gerar conselho;
    // sessão quente ou pequena demais não gera.
    func testColdCacheSessionTriggersAdvice() {
        let session = SessionUsage(tokens: TokenUsage(input: 140_000, output: 40_000, cacheWrite: 0, cacheRead: 20_000))
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok, session: session)
        let advice = DecisionAdvisor.advise(snapshots: [.claudeCode: snapshot], budget: nil)
        XCTAssertTrue(advice.contains { $0.title == "Sessão fria de cache" })
        XCTAssertTrue(advice.contains { $0.detail.contains("10%") })
    }

    func testWarmCacheSessionDoesNotTriggerAdvice() {
        let session = SessionUsage(tokens: TokenUsage(input: 30_000, output: 10_000, cacheWrite: 5_000, cacheRead: 55_000))
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok, session: session)
        let advice = DecisionAdvisor.advise(snapshots: [.claudeCode: snapshot], budget: nil)
        XCTAssertFalse(advice.contains { $0.title == "Sessão fria de cache" })
    }

    // REGRESSÃO: modelo mais caro ≥ 40% da sessão gera conselho; dominância
    // de modelo barato não gera.
    func testDominantExpensiveModelTriggersAdvice() {
        let session = SessionUsage(modelTokens: [
            "claude-opus-5": TokenUsage(input: 80_000, output: 20_000, cacheWrite: 0, cacheRead: 0),
            "claude-sonnet-5": TokenUsage(input: 25_000, output: 0, cacheWrite: 0, cacheRead: 0),
        ])
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok, session: session)
        let advice = DecisionAdvisor.advise(snapshots: [.claudeCode: snapshot], budget: nil)
        XCTAssertTrue(advice.contains { $0.title == "Modelo mais caro dominando" })
    }

    func testBalancedModelsDoesNotTriggerAdvice() {
        let session = SessionUsage(modelTokens: [
            "claude-opus-5": TokenUsage(input: 10_000, output: 2_000, cacheWrite: 0, cacheRead: 0),
            "claude-sonnet-5": TokenUsage(input: 90_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
        ])
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok, session: session)
        let advice = DecisionAdvisor.advise(snapshots: [.claudeCode: snapshot], budget: nil)
        XCTAssertFalse(advice.contains { $0.title == "Modelo mais caro dominando" })
    }

    // REGRESSÃO: cota própria do Fable ≥ 70% gera conselho; abaixo não.
    func testFablePoolHighTriggersAdvice() {
        let session = SessionUsage(namedQuotas: [NamedQuota(name: "Fable 5", usedPercent: 82, resetsAt: Date())])
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok, session: session)
        let advice = DecisionAdvisor.advise(snapshots: [.claudeCode: snapshot], budget: nil)
        XCTAssertTrue(advice.contains { $0.title == "Fable 5: cota própria" })
    }

    func testFablePoolLowDoesNotTriggerAdvice() {
        let session = SessionUsage(namedQuotas: [NamedQuota(name: "Fable 5", usedPercent: 40, resetsAt: Date())])
        let snapshot = UsageSnapshot(provider: .claudeCode, health: .ok, session: session)
        let advice = DecisionAdvisor.advise(snapshots: [.claudeCode: snapshot], budget: nil)
        XCTAssertFalse(advice.contains { $0.title == "Fable 5: cota própria" })
    }
}
