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
    // runner em GAME OVER na MESMA tela. Semanal exausto → veredito de
    // bloqueio, nunca promessa de segurança.
    func testBurnVerdictWeeklyExhaustedNeverReadsSafe() {
        let verdict = NotchExpandedView.burnVerdict(projection: nil, hasSamples: true, weeklyExhausted: true)
        XCTAssertTrue(verdict.text.contains("Weekly limit exhausted"))
        XCTAssertFalse(verdict.text.contains("safe"), "an exhausted weekly cap must never read as safe")
    }

    func testBurnVerdictWeeklyExhaustedBeatsBurnProjection() {
        let projection = BurnRate.Projection(percentPerHour: 5, exhaustsAt: nil)
        let verdict = NotchExpandedView.burnVerdict(projection: projection, hasSamples: true, weeklyExhausted: true)
        XCTAssertTrue(verdict.text.contains("Weekly limit exhausted"))
    }

    func testBurnVerdictWeeklyExhaustedWithoutSamplesStillBlocked() {
        // Sem samples ainda (sessão acabou de resetar): nada de
        // "Collecting samples" com o semanal estourado.
        let verdict = NotchExpandedView.burnVerdict(projection: nil, hasSamples: false, weeklyExhausted: true)
        XCTAssertTrue(verdict.text.contains("Weekly limit exhausted"))
    }

    func testBurnVerdictHealthyWeeklyKeepsSafeVerdict() {
        let verdict = NotchExpandedView.burnVerdict(projection: nil, hasSamples: true, weeklyExhausted: false)
        XCTAssertEqual(verdict.text, "No burn right now — safe until the reset.")
    }

    func testBurnVerdictHealthyWeeklyKeepsProjectionVerdict() {
        let projection = BurnRate.Projection(percentPerHour: 5, exhaustsAt: nil)
        let verdict = NotchExpandedView.burnVerdict(projection: projection, hasSamples: true, weeklyExhausted: false)
        XCTAssertTrue(verdict.text.contains("safe until reset"))
    }
}
