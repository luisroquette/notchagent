import XCTest
@testable import NotchAgent

final class ProviderCardViewTests: XCTestCase {
    private func snapshot(session: Double?, weekly: Double?, weeklyResets: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: session.map { SessionUsage(resetsAt: Date(), usedPercent: $0) },
            weekly: weekly.map { WeeklyUsage(usedPercent: $0, resetsAt: weeklyResets) }
        )
    }

    func testSecondaryScopeReturnsWeeklyWhenBothScopesPresent() {
        let reset = Date(timeIntervalSince1970: 1_700_000_000)
        let scope = ProviderCardView.secondaryScope(snapshot(session: 10, weekly: 55, weeklyResets: reset))
        XCTAssertEqual(scope?.usedPercent, 55)
        XCTAssertEqual(scope?.resetsAt, reset)
    }

    func testSecondaryScopeNilWhenOnlySession() {
        XCTAssertNil(ProviderCardView.secondaryScope(snapshot(session: 10, weekly: nil)))
    }

    func testSecondaryScopeNilWhenOnlyWeekly() {
        // Headline já É o weekly nesse caso — não duplicar.
        XCTAssertNil(ProviderCardView.secondaryScope(snapshot(session: nil, weekly: 55)))
    }

    func testSecondaryScopeNilWhenNeither() {
        XCTAssertNil(ProviderCardView.secondaryScope(snapshot(session: nil, weekly: nil)))
    }

    func testSecondaryScopeNilWhenWeeklyHasNoPercent() {
        // Weekly com só tokens (sem percent oficial) não pode fabricar número.
        let snap = UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: SessionUsage(resetsAt: Date(), usedPercent: 10),
            weekly: WeeklyUsage(usedPercent: nil, resetsAt: Date())
        )
        XCTAssertNil(ProviderCardView.secondaryScope(snap))
    }
}

// MARK: - Session-primary layout (weekly-only plans, e.g. Codex Pro)

extension ProviderCardViewTests {
    private func weeklyOnlySnapshot(sessionTokens: TokenUsage, sessionPercent: Double? = nil) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            health: .ok,
            session: SessionUsage(
                tokens: sessionTokens,
                startedAt: Date(timeIntervalSince1970: 1_700_000_100),
                usedPercent: sessionPercent
            ),
            weekly: WeeklyUsage(usedPercent: 55, resetsAt: Date(timeIntervalSince1970: 1_700_000_000))
        )
    }

    func testSessionPrimaryLayoutWhenWeeklyOnlyAndSessionTokens() {
        let snap = weeklyOnlySnapshot(sessionTokens: TokenUsage(input: 5_000, output: 2_000))
        let layout = ProviderCardView.sessionPrimaryLayout(snap)
        XCTAssertEqual(layout?.tokens.total, 7_000)
        XCTAssertEqual(layout?.startedAt, Date(timeIntervalSince1970: 1_700_000_100))
    }

    func testSessionPrimaryLayoutNilWhenSessionPercentExists() {
        let snap = weeklyOnlySnapshot(sessionTokens: TokenUsage(input: 5_000, output: 2_000), sessionPercent: 10)
        XCTAssertNil(ProviderCardView.sessionPrimaryLayout(snap))
    }

    func testSessionPrimaryLayoutNilWhenSessionHasNoTokens() {
        XCTAssertNil(ProviderCardView.sessionPrimaryLayout(weeklyOnlySnapshot(sessionTokens: .zero)))
    }

    func testSessionPrimaryLayoutNilWhenNoGauge() {
        let snap = UsageSnapshot(provider: .codex, health: .ok)
        XCTAssertNil(ProviderCardView.sessionPrimaryLayout(snap))
    }
}

// MARK: - Session percent estimate labeling (budget fallback)

extension ProviderCardViewTests {
    private func snapshotWithSessionOrigin(_ fromQuota: Bool?) -> UsageSnapshot {
        var session = SessionUsage(resetsAt: Date(), usedPercent: 40)
        session.usedPercentIsFromQuota = fromQuota
        return UsageSnapshot(provider: .claudeCode, health: .ok, session: session)
    }

    func testSessionPercentPrefixEmptyWhenOfficialOrUnknown() {
        XCTAssertEqual(ProviderCardView.sessionPercentPrefix(snapshotWithSessionOrigin(true)), "")
        XCTAssertEqual(ProviderCardView.sessionPercentPrefix(snapshotWithSessionOrigin(nil)), "")
    }

    func testSessionPercentPrefixTildeWhenEstimated() {
        XCTAssertEqual(ProviderCardView.sessionPercentPrefix(snapshotWithSessionOrigin(false)), "~")
    }

    func testSessionLabelMarksEstimate() {
        let metric = GaugeMetric(used: 40, isWeekly: false)
        XCTAssertEqual(ProviderCardView.sessionLabel(snapshotWithSessionOrigin(false), metric: metric), "OF 5H SESSION LEFT · ESTIMATED")
        XCTAssertEqual(ProviderCardView.sessionLabel(snapshotWithSessionOrigin(true), metric: metric), "OF 5H SESSION LEFT")
    }

    func testSessionLabelWeeklyNeverMarked() {
        let metric = GaugeMetric(used: 40, isWeekly: true)
        XCTAssertEqual(ProviderCardView.sessionLabel(snapshotWithSessionOrigin(false), metric: metric), "OF WEEKLY LIMIT LEFT")
    }
}

// MARK: - Provider mascot mapping

extension ProviderCardViewTests {
    func testMascotNameMapsActiveModelFamily() {
        XCTAssertEqual(ProviderCardView.mascotName(for: "claude-sonnet-4-6"), "claude-sonnet")
        XCTAssertEqual(ProviderCardView.mascotName(for: "claude-fable-5"), "claude-fable")
        XCTAssertEqual(ProviderCardView.mascotName(for: "claude-opus-4-8"), "claude-opus")
        XCTAssertEqual(ProviderCardView.mascotName(for: "claude-haiku-4-5-20251001"), "claude-haiku")
    }

    func testMascotNameFallsBackToSonnet() {
        XCTAssertEqual(ProviderCardView.mascotName(for: nil), "claude-sonnet")
        XCTAssertEqual(ProviderCardView.mascotName(for: "gpt-5.3-codex-spark"), "claude-sonnet")
    }
}
