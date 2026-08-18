import XCTest
@testable import NotchAgent

final class PayloadAdvisorTests: XCTestCase {
    private func makePayload(tools: [String: TokenUsage], agentSplit: SessionInsightsPayload.AgentSplit? = nil,
                             topMessages: [SessionInsightsPayload.TopMessage] = []) -> SessionInsightsPayload {
        var records: [PayloadBuilder.MessageRecord] = []
        for (tool, tokens) in tools {
            records.append(.init(timestamp: .now, requestId: "r-\(tool)", model: "m",
                                 tokens: tokens, toolNames: [tool]))
        }
        var payload = PayloadBuilder.build(
            provider: .claudeCode,
            window: DateInterval(start: .distantPast, end: .distantFuture),
            records: records, agentSplit: agentSplit)
        // topMessages é derivado pelo builder; para o caso de operação pesada
        // construímos o payload diretamente para controlar o conteúdo.
        if !topMessages.isEmpty {
            payload = SessionInsightsPayload(
                generatedAt: .now, provider: .claudeCode,
                window: DateInterval(start: .distantPast, end: .distantFuture),
                aggregate: payload.aggregate, cacheShare: payload.cacheShare,
                tokensByTool: payload.tokensByTool, tokensByModel: payload.tokensByModel,
                agentSplit: payload.agentSplit, topMessages: topMessages,
                preview: payload.preview)
        }
        return payload
    }

    // REGRESSÃO: ferramenta ≥ 40% dos tokens da sessão vira conselho.
    func testDominantToolTriggersAdvice() {
        let payload = makePayload(tools: [
            "Read": TokenUsage(input: 80_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
            "Bash": TokenUsage(input: 20_000, output: 1_000, cacheWrite: 0, cacheRead: 0),
        ])
        let advice = PayloadAdvisor.advise(payload)
        XCTAssertTrue(advice.contains { $0.title == "Ferramenta dominante: Read" })
        XCTAssertTrue(advice.contains { $0.detail.contains("80%") })
    }

    // REGRESSÃO: subagentes ≥ 50% da sessão vira conselho de warning.
    func testSubagentDominanceTriggersAdvice() {
        let payload = makePayload(
            tools: ["Read": TokenUsage(input: 10_000, output: 0, cacheWrite: 0, cacheRead: 40_000)],
            agentSplit: .init(main: TokenUsage(input: 10_000, output: 0, cacheWrite: 0, cacheRead: 15_000),
                              subagent: TokenUsage(input: 40_000, output: 0, cacheWrite: 0, cacheRead: 25_000)))
        let advice = PayloadAdvisor.advise(payload)
        XCTAssertTrue(advice.contains { $0.title == "Subagentes dominando" })
        XCTAssertEqual(advice.first { $0.title == "Subagentes dominando" }?.severity, .warning)
    }

    // REGRESSÃO: uma única operação ≥ 30% da sessão vira conselho.
    func testSingleHeavyMessageTriggersAdvice() {
        let payload = makePayload(
            tools: ["Read": TokenUsage(input: 30_000, output: 0, cacheWrite: 0, cacheRead: 60_000)],
            topMessages: [.init(requestId: "heavy", timestamp: .now, model: "m",
                                tokens: TokenUsage(input: 30_000, output: 0, cacheWrite: 0, cacheRead: 60_000),
                                toolNames: ["Read"])])
        let advice = PayloadAdvisor.advise(payload)
        XCTAssertTrue(advice.contains { $0.title == "Operação única pesada" })
    }

    // REGRESSÃO: sessão balanceada (4 ferramentas ~25%, top mensagem < 30%,
    // sem subagentes) não gera conselho de payload.
    func testBalancedSessionProducesNoAdvice() {
        let payload = makePayload(tools: [
            "Read": TokenUsage(input: 20_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
            "Bash": TokenUsage(input: 20_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
            "Write": TokenUsage(input: 20_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
            "Glob": TokenUsage(input: 20_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
        ])
        XCTAssertTrue(PayloadAdvisor.advise(payload).isEmpty)
    }
}
