import XCTest
@testable import NotchAgent

/// REGRESSÃO (19/08/2026): quando a janela de 5h do Codex reinicia, o
/// percentual OFICIAL da sessão (usedPercentIsFromQuota == true, vindo do
/// rollout) voltava a pintar "100% OF 5H SESSION LEFT" em VERDE — mesmo com
/// o limite semanal a 0% left ("Você atingiu o limite de uso; tente
/// novamente em 22/08 09:46"). A janela de 5h é SUBORDINADA à semanal:
/// exausto, o semanal vence SEMPRE — sessão oficial ou estimada. A sessão
/// só é headline enquanto o semanal tem folga. Este contrato substitui o
/// antigo "official session beats exhausted weekly" (ver
/// ExhaustedWeeklyBeatsEstimatedSessionTests).
final class ExhaustedWeeklyBeatsOfficialSessionTests: XCTestCase {
    private func snapshot(sessionPercent: Double?, weeklyPercent: Double?) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            health: .ok,
            session: sessionPercent.map {
                SessionUsage(
                    tokens: TokenUsage(input: 7_000_000, output: 0),
                    resetsAt: Date().addingTimeInterval(3000),
                    usedPercent: $0,
                    usedPercentIsFromQuota: true
                )
            },
            weekly: weeklyPercent.map {
                WeeklyUsage(usedPercent: $0, resetsAt: Date().addingTimeInterval(172_800))
            }
        )
    }

    func testFreshOfficialSessionDoesNotMaskExhaustedWeekly() {
        // Caso do usuário: 5h recém-resetada a ~0% usado (oficial), semanal a 100%.
        let metric = GaugeMetric.from(snapshot(sessionPercent: 0.14, weeklyPercent: 100))
        XCTAssertEqual(metric?.used, 100)
        XCTAssertEqual(metric?.remaining, 0)
        XCTAssertTrue(metric?.isWeekly ?? false, "exhausted weekly must headline even against an official session percent")
    }

    func testMidSessionOfficialPercentStillLosesToExhaustedWeekly() {
        let metric = GaugeMetric.from(snapshot(sessionPercent: 50, weeklyPercent: 100))
        XCTAssertEqual(metric?.used, 100)
        XCTAssertTrue(metric?.isWeekly ?? false)
    }

    func testWeeklyJustUnderThresholdKeepsOfficialSessionHeadline() {
        let metric = GaugeMetric.from(snapshot(sessionPercent: 50, weeklyPercent: 99.4))
        XCTAssertEqual(metric?.used, 50)
        XCTAssertFalse(metric?.isWeekly ?? true)
    }

    func testExhaustedSessionAndExhaustedWeeklyHeadlineWeeklyReset() {
        // Ambos esgotados: quem desbloqueia é o semanal — o gauge (e o
        // "NEW RUN" do runner) deve apontar o reset semanal, não o da 5h.
        let metric = GaugeMetric.from(snapshot(sessionPercent: 100, weeklyPercent: 100))
        XCTAssertEqual(metric?.used, 100)
        XCTAssertTrue(metric?.isWeekly ?? false)
    }

    func testHealthyWeeklyKeepsOfficialSession() {
        let metric = GaugeMetric.from(snapshot(sessionPercent: 50, weeklyPercent: 25))
        XCTAssertEqual(metric?.used, 50)
        XCTAssertFalse(metric?.isWeekly ?? true)
    }

    func testSessionOnlyUnaffected() {
        let metric = GaugeMetric.from(snapshot(sessionPercent: 30, weeklyPercent: nil))
        XCTAssertEqual(metric?.used, 30)
        XCTAssertFalse(metric?.isWeekly ?? true)
    }

    func testBlockedStillWinsOverEverything() {
        var snap = snapshot(sessionPercent: 0.14, weeklyPercent: 100)
        snap.quotaStatus = .blocked
        let metric = GaugeMetric.from(snap)
        XCTAssertEqual(metric?.used, 100)
    }
}
