import XCTest
@testable import NotchAgent

final class PayloadBuilderParityTests: XCTestCase {
    func testPreviewIsDerivedFromSameFieldsPanelUses() {
        let records = [
            PayloadBuilder.MessageRecord(timestamp: .now, requestId: "a", model: "m",
                tokens: TokenUsage(input: 60_000, output: 10_000, cacheWrite: 0, cacheRead: 5_000),
                toolNames: ["Read"]),
            PayloadBuilder.MessageRecord(timestamp: .now, requestId: "b", model: "m",
                tokens: TokenUsage(input: 20_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
                toolNames: ["Read", "Bash"]),
            // Mensagem só de cache (sem ferramenta) para a sessão NÃO ser
            // fria de cache — isolando o branch de ferramenta dominante.
            PayloadBuilder.MessageRecord(timestamp: .now, requestId: "c", model: "m",
                tokens: TokenUsage(input: 40_000, output: 0, cacheWrite: 0, cacheRead: 60_000),
                toolNames: []),
        ]
        let payload = PayloadBuilder.build(provider: .claudeCode, window: .init(start: .distantPast, end: .distantFuture), records: records)
        // Read: 100k de 200k = 50% → dominante ≥ 40%
        XCTAssertEqual(payload.preview.line, "Topo: Read 50%")
        XCTAssertEqual(payload.preview.tier, .watch)
        // O painel lê tokensByTool — MESMO objeto de onde o preview derivou
        XCTAssertEqual(payload.tokensByTool["Read"], TokenUsage(input: 80_000, output: 15_000, cacheWrite: 0, cacheRead: 5_000))
    }

    func testWarmCacheBalancedPreview() {
        // cache 44% (não fria), ferramenta topo 38,8% (< 40%) → equilibrada
        let payload = PayloadBuilder.build(provider: .claudeCode, window: .init(start: .distantPast, end: .distantFuture), records: [
            .init(timestamp: .now, requestId: "a", model: "m",
                  tokens: TokenUsage(input: 5_000, output: 4_000, cacheWrite: 0, cacheRead: 10_000), toolNames: ["Read"]),
            .init(timestamp: .now, requestId: "b", model: "m",
                  tokens: TokenUsage(input: 5_000, output: 3_000, cacheWrite: 0, cacheRead: 7_000), toolNames: ["Bash"]),
            .init(timestamp: .now, requestId: "c", model: "m",
                  tokens: TokenUsage(input: 8_000, output: 2_000, cacheWrite: 0, cacheRead: 5_000), toolNames: ["Write"]),
        ])
        XCTAssertEqual(payload.preview.line, "Sessão equilibrada")
        XCTAssertEqual(payload.preview.tier, .ok)
    }

    func testColdCachePreviewBeatsToolDominance() {
        // cache ~10% < 25% e ferramenta dominante: cache frio é o sinal mais grave
        let payload = PayloadBuilder.build(provider: .claudeCode, window: .init(start: .distantPast, end: .distantFuture), records: [
            .init(timestamp: .now, requestId: "a", model: "m",
                  tokens: TokenUsage(input: 90_000, output: 5_000, cacheWrite: 0, cacheRead: 10_000), toolNames: ["Read"]),
        ])
        XCTAssertEqual(payload.preview.tier, .watch)
        XCTAssertTrue(payload.preview.line.contains("Cache"))
    }

    func testTopMessagesCappedAndSorted() {
        let records = (0..<5).map { i in
            PayloadBuilder.MessageRecord(timestamp: .now, requestId: "r\(i)", model: "m",
                tokens: TokenUsage(input: 1_000 * (i + 1), output: 0, cacheWrite: 0, cacheRead: 0), toolNames: [])
        }
        let payload = PayloadBuilder.build(provider: .claudeCode, window: .init(start: .distantPast, end: .distantFuture), records: records, topN: 3)
        XCTAssertEqual(payload.topMessages.map(\.requestId), ["r4", "r3", "r2"])
    }
}
