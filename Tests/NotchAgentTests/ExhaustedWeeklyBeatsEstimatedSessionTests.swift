import XCTest
@testable import NotchAgent

/// REGRESSÃO: card do Codex mostrava "~100% OF 5H SESSION LEFT · ESTIMATED"
/// em VERDE enquanto o semanal oficial estava em 0% left (OpenAI: "Você
/// atingiu o limite de uso por enquanto"). A estimativa de budget local
/// NUNCA pode mascarar um bloqueio semanal oficial — semanal exausto vira o
/// headline, em vermelho.
final class ExhaustedWeeklyBeatsEstimatedSessionTests: XCTestCase {
    private func snapshot(
        sessionPercent: Double?,
        sessionFromQuota: Bool?,
        weeklyPercent: Double?
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            health: .ok,
            session: sessionPercent.map {
                SessionUsage(
                    tokens: TokenUsage(input: 7_000_000, output: 0),
                    resetsAt: Date().addingTimeInterval(3000),
                    usedPercent: $0,
                    usedPercentIsFromQuota: sessionFromQuota
                )
            },
            weekly: weeklyPercent.map { WeeklyUsage(usedPercent: $0) }
        )
    }

    func testExhaustedWeeklyBeatsEstimatedSession() {
        // Caso real do usuário: estimate diz ~0% usado, semanal oficial a 100%.
        let metric = GaugeMetric.from(snapshot(sessionPercent: 0.14, sessionFromQuota: false, weeklyPercent: 100))
        XCTAssertEqual(metric?.used, 100, "weekly exhausted must override the budget estimate")
        XCTAssertEqual(metric?.remaining, 0)
        XCTAssertTrue(metric?.isWeekly ?? false, "headline must read as the weekly cap")
    }

    func testExhaustedWeeklyJustUnder100StillBeatsEstimate() {
        let metric = GaugeMetric.from(snapshot(sessionPercent: 0.14, sessionFromQuota: false, weeklyPercent: 99.6))
        XCTAssertEqual(metric?.used, 100)
        XCTAssertTrue(metric?.isWeekly ?? false)
    }

    func testHealthyWeeklyKeepsEstimatedSessionHeadline() {
        // Semanal com folga: a estimativa continua sendo o headline (com "~").
        let metric = GaugeMetric.from(snapshot(sessionPercent: 5, sessionFromQuota: false, weeklyPercent: 25))
        XCTAssertEqual(metric?.used, 5)
        XCTAssertFalse(metric?.isWeekly ?? true)
    }

    func testOfficialSessionStillBeatsExhaustedWeekly() {
        // Claude: percent oficial da janela de 5h tem precedência — o weekly
        // exausto aparece como bloco secundário, não rouba o headline.
        let metric = GaugeMetric.from(snapshot(sessionPercent: 50, sessionFromQuota: true, weeklyPercent: 100))
        XCTAssertEqual(metric?.used, 50)
        XCTAssertFalse(metric?.isWeekly ?? true)
    }

    func testLegacyNilFromQuotaFieldTreatedAsEstimate() {
        // Snapshot antigo sem o campo (nil = não quota-backed, contrato do
        // Usage.swift): semanal exausto vence do mesmo jeito.
        let metric = GaugeMetric.from(snapshot(sessionPercent: 0.14, sessionFromQuota: nil, weeklyPercent: 100))
        XCTAssertEqual(metric?.used, 100)
        XCTAssertTrue(metric?.isWeekly ?? false)
    }

    func testBlockedQuotaStatusStillWinsOverEverything() {
        // O caminho blocked existente não pode ser afetado pela regra nova.
        var snap = snapshot(sessionPercent: 0.14, sessionFromQuota: false, weeklyPercent: 100)
        snap.quotaStatus = .blocked
        let metric = GaugeMetric.from(snap)
        XCTAssertEqual(metric?.used, 100)
    }
}
