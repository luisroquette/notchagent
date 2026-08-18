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
