import XCTest
@testable import NotchAgent

final class NotchExpandedViewTests: XCTestCase {
    func testPanelStripProvidersExcludesGemini() {
        // Gemini CLI strip removed from the panel — unused, "NOT INSTALLED"
        // noise. The provider keeps working internally (settings, snapshots).
        XCTAssertFalse(NotchExpandedView.panelStripProviders.contains(.geminiCLI))
    }

    func testPanelStripProvidersKeepsOtherStrips() {
        XCTAssertTrue(NotchExpandedView.panelStripProviders.contains(.apiAccounts))
    }

    func testPanelCardProvidersAreClaudeAndCodex() {
        XCTAssertEqual(NotchExpandedView.panelCardProviders, [.claudeCode, .codex])
    }

    // REGRESSÃO 19/08/2026: a página BURN dizia "No burn right now — safe
    // until the reset." (verde) enquanto o semanal estava a 0% left e o
    // runner em GAME OVER na MESMA tela. Gauge esgotado → veredito de
    // bloqueio, nunca promessa de segurança.
    func testBurnVerdictWeeklyExhaustedNeverReadsSafe() {
        let verdict = NotchExpandedView.burnVerdict(projection: nil, hasSamples: true, gaugeExhausted: true, isWeekly: true)
        XCTAssertTrue(verdict.text.contains("Weekly limit exhausted"))
        XCTAssertFalse(verdict.text.contains("safe"), "an exhausted weekly cap must never read as safe")
    }

    func testBurnVerdictWeeklyExhaustedBeatsBurnProjection() {
        let projection = BurnRate.Projection(percentPerHour: 5, exhaustsAt: nil)
        let verdict = NotchExpandedView.burnVerdict(projection: projection, hasSamples: true, gaugeExhausted: true, isWeekly: true)
        XCTAssertTrue(verdict.text.contains("Weekly limit exhausted"))
    }

    func testBurnVerdictWeeklyExhaustedWithoutSamplesStillBlocked() {
        // Sem samples ainda (sessão acabou de resetar): nada de
        // "Collecting samples" com o semanal estourado.
        let verdict = NotchExpandedView.burnVerdict(projection: nil, hasSamples: false, gaugeExhausted: true, isWeekly: true)
        XCTAssertTrue(verdict.text.contains("Weekly limit exhausted"))
    }

    // REGRESSÃO 20/08/2026: o Claude BLOCKED com sessão fresh (isWeekly
    // false no gauge) ainda pintava "100% LEFT — safe until the reset"
    // ao lado do GAME OVER do runner. O esgotamento do gauge vale para
    // QUALQUER janela, não só a semanal.
    func testBurnVerdictBlockedSessionNeverReadsSafe() {
        let verdict = NotchExpandedView.burnVerdict(projection: nil, hasSamples: true, gaugeExhausted: true, isWeekly: false)
        XCTAssertTrue(verdict.text.contains("5h window exhausted"))
        XCTAssertFalse(verdict.text.contains("safe"), "a blocked session must never read as safe")
    }

    func testBurnVerdictBlockedSessionBeatsBurnProjection() {
        let projection = BurnRate.Projection(percentPerHour: 5, exhaustsAt: nil)
        let verdict = NotchExpandedView.burnVerdict(projection: projection, hasSamples: true, gaugeExhausted: true, isWeekly: false)
        XCTAssertTrue(verdict.text.contains("5h window exhausted"))
    }

    func testBurnVerdictBlockedSessionWithoutSamplesStillBlocked() {
        let verdict = NotchExpandedView.burnVerdict(projection: nil, hasSamples: false, gaugeExhausted: true, isWeekly: false)
        XCTAssertTrue(verdict.text.contains("5h window exhausted"))
    }

    func testBurnVerdictHealthyWeeklyKeepsSafeVerdict() {
        let verdict = NotchExpandedView.burnVerdict(projection: nil, hasSamples: true, gaugeExhausted: false)
        XCTAssertEqual(verdict.text, "No burn right now — safe until the reset.")
    }

    func testBurnVerdictHealthyWeeklyKeepsProjectionVerdict() {
        let projection = BurnRate.Projection(percentPerHour: 5, exhaustsAt: nil)
        let verdict = NotchExpandedView.burnVerdict(projection: projection, hasSamples: true, gaugeExhausted: false)
        XCTAssertTrue(verdict.text.contains("safe until reset"))
    }
}
