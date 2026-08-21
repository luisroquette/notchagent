import XCTest
@testable import NotchAgent

/// REGRESSÃO (21/08): Codex models are independent quota pools, not a
/// shared account-wide budget — verified empirically: hitting a 429 on
/// GPT-5.3-Codex-Spark, then switching to another model, worked
/// immediately with no wait. The old rule picked the WORST model as the
/// headline ("worst case always wins"), which is correct for a single
/// shared cap (Claude) but wrong here: it painted the whole Codex card
/// red/exhausted over one model, even though other models kept working.
final class CodexIndependentModelQuotaTests: XCTestCase {
    private func scope(usedPercent: Double, resetsIn: TimeInterval = 3600) -> CodexProvider.WeeklyScope {
        CodexProvider.WeeklyScope(
            window: CodexRateWindow(usedPercent: usedPercent, windowMinutes: 10080, resetsAt: Date().addingTimeInterval(resetsIn)),
            observedAt: Date()
        )
    }

    // The headline must surface the model with the MOST headroom — "here's
    // at least one thing you can still use" — not the exhausted one.
    func testPrimaryWeeklyScopeUsesMostHeadroomNotLeast() {
        let scopes: [String: CodexProvider.WeeklyScope] = [
            "gpt-5.3-codex-spark": scope(usedPercent: 100),
            "gpt-5.6-sol": scope(usedPercent: 12),
        ]
        let picked = CodexProvider.primaryWeeklyScope(among: scopes)
        XCTAssertEqual(picked?.window.usedPercent, 12, "must surface the model with room, not the exhausted one")
    }

    // With only one model ever seen and it's exhausted, there's nothing
    // better to report — this is the honest floor, not a regression.
    func testPrimaryWeeklyScopeSingleExhaustedModelStillReturnsIt() {
        let scopes: [String: CodexProvider.WeeklyScope] = [
            "gpt-5.3-codex-spark": scope(usedPercent: 100),
        ]
        XCTAssertEqual(CodexProvider.primaryWeeklyScope(among: scopes)?.window.usedPercent, 100)
    }

    // Every known model exhausted → still the worst (and only) honest
    // reading; nothing better exists in the data to report instead.
    func testPrimaryWeeklyScopeAllExhaustedReturnsWorst() {
        let scopes: [String: CodexProvider.WeeklyScope] = [
            "gpt-5.3-codex-spark": scope(usedPercent: 100),
            "gpt-5.6-sol": scope(usedPercent: 99.8),
        ]
        XCTAssertEqual(CodexProvider.primaryWeeklyScope(among: scopes)?.window.usedPercent, 99.8)
    }

    func testPrimaryWeeklyScopeEmptyIsNil() {
        XCTAssertNil(CodexProvider.primaryWeeklyScope(among: [:]))
    }
}
