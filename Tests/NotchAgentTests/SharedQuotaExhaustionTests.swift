import XCTest
@testable import NotchAgent

/// REGRESSÃO: zeramento em cascata quando a janela compartilhada estoura.
/// Não há separação de uso por modelo — estourou a janela (5h Claude) ou o
/// semanal (Claude/OpenAI), TODOS os modelos do pool compartilhado ficam
/// inutilizáveis, independente do que um probe individual de disponibilidade
/// reportar. Cotas próprias (Fable 5, GPT-5.3-Codex-Spark) ficam de fora.
@MainActor
final class SharedQuotaExhaustionTests: XCTestCase {
    private func snapshot(
        quotaStatus: QuotaStatus? = nil,
        sessionPercent: Double? = nil,
        sessionPercentFromQuota: Bool? = nil,
        weeklyPercent: Double? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: sessionPercent.map {
                SessionUsage(
                    tokens: .zero,
                    startedAt: Date(),
                    resetsAt: Date(),
                    usedPercent: $0,
                    usedPercentIsFromQuota: sessionPercentFromQuota
                )
            },
            weekly: weeklyPercent.map { WeeklyUsage(tokens: .zero, usedPercent: $0) },
            quotaStatus: quotaStatus
        )
    }

    // MARK: sharedPoolExhausted

    func testExhaustedWhenQuotaStatusBlocked() {
        XCTAssertTrue(NotchExpandedView.sharedPoolExhausted(snapshot(quotaStatus: .blocked)))
    }

    func testNotExhaustedWhenQuotaStatusOk() {
        XCTAssertFalse(NotchExpandedView.sharedPoolExhausted(snapshot(quotaStatus: .ok)))
    }

    func testExhaustedWhenOfficialSessionPercentAt100() {
        XCTAssertTrue(NotchExpandedView.sharedPoolExhausted(
            snapshot(sessionPercent: 100, sessionPercentFromQuota: true)
        ))
    }

    func testNotExhaustedWhenSessionPercentIsBudgetEstimate() {
        // Percent de orçamento local (Codex) NÃO é bloqueio real — o usuário
        // pode seguir usando o pool mesmo com o budget estimado estourado.
        XCTAssertFalse(NotchExpandedView.sharedPoolExhausted(
            snapshot(sessionPercent: 100, sessionPercentFromQuota: false)
        ))
    }

    func testNotExhaustedWhenSessionPercentIsNilLegacyDecode() {
        // Snapshot antigo sem o campo: tratar como estimativa, não bloqueio.
        XCTAssertFalse(NotchExpandedView.sharedPoolExhausted(
            snapshot(sessionPercent: 100, sessionPercentFromQuota: nil)
        ))
    }

    func testExhaustedWhenWeeklyPercentAt100() {
        XCTAssertTrue(NotchExpandedView.sharedPoolExhausted(snapshot(weeklyPercent: 100)))
    }

    func testExhaustedWhenWeeklyPercentJustUnder100() {
        XCTAssertTrue(NotchExpandedView.sharedPoolExhausted(snapshot(weeklyPercent: 99.6)))
    }

    func testNotExhaustedWhenPercentsLow() {
        XCTAssertFalse(NotchExpandedView.sharedPoolExhausted(
            snapshot(sessionPercent: 40, sessionPercentFromQuota: true, weeklyPercent: 12)
        ))
    }

    func testNotExhaustedWhenSnapshotHasNothing() {
        XCTAssertFalse(NotchExpandedView.sharedPoolExhausted(snapshot()))
    }

    // MARK: modelHasOwnQuota

    func testSparkModelHasOwnQuota() {
        let quotas = [NamedQuota(name: "GPT-5.3-Codex-Spark", usedPercent: 30)]
        XCTAssertTrue(NotchExpandedView.modelHasOwnQuota("gpt-5.3-codex-spark", namedQuotas: quotas))
    }

    func testSharedModelDoesNotMatchSparkQuota() {
        let quotas = [NamedQuota(name: "GPT-5.3-Codex-Spark", usedPercent: 30)]
        XCTAssertFalse(NotchExpandedView.modelHasOwnQuota("gpt-5.6-sol", namedQuotas: quotas))
    }

    func testNoOwnQuotaWhenNamedQuotasEmpty() {
        XCTAssertFalse(NotchExpandedView.modelHasOwnQuota("gpt-5.3-codex-spark", namedQuotas: []))
    }
}
