import XCTest
@testable import NotchAgent

/// LAYOUT INVARIÁVEL (20/08/2026): o card da página Now mostra SEMPRE dois
/// blocos fixos — sessão 5h acima, janela semanal abaixo — para Claude E
/// Codex. Os helpers adaptativos antigos (secondaryScope,
/// sessionPrimaryLayout, weeklyOverridesHeadline) foram removidos junto com
/// o layout que os usava; o guard estrutural
/// QuotaHierarchyContractTests exige a ordem física dos blocos no fonte.
@MainActor
final class ProviderCardViewTests: XCTestCase {
    private func snapshotWithSessionOrigin(_ fromQuota: Bool?) -> UsageSnapshot {
        var session = SessionUsage(resetsAt: Date(), usedPercent: 40)
        session.usedPercentIsFromQuota = fromQuota
        return UsageSnapshot(provider: .claudeCode, health: .ok, session: session)
    }

    // MARK: - Session percent estimate labeling (budget fallback)

    func testSessionPercentPrefixEmptyWhenOfficialOrUnknown() {
        XCTAssertEqual(ProviderCardView.sessionPercentPrefix(snapshotWithSessionOrigin(true)), "")
        XCTAssertEqual(ProviderCardView.sessionPercentPrefix(snapshotWithSessionOrigin(nil)), "")
    }

    func testSessionPercentPrefixTildeWhenEstimated() {
        XCTAssertEqual(ProviderCardView.sessionPercentPrefix(snapshotWithSessionOrigin(false)), "~")
    }

    func testSessionLabelMarksEstimate() {
        XCTAssertEqual(ProviderCardView.sessionLabel(snapshotWithSessionOrigin(false)), "OF 5H SESSION LEFT · ESTIMATED")
        XCTAssertEqual(ProviderCardView.sessionLabel(snapshotWithSessionOrigin(true)), "OF 5H SESSION LEFT")
    }

    func testSessionLabelNeverSwitchesWindows() {
        // O label do bloco de cima é SEMPRE a sessão 5h — nunca "WEEKLY",
        // qualquer que seja o estado do gauge (o bloco semanal vive abaixo).
        XCTAssertEqual(ProviderCardView.sessionLabel(snapshotWithSessionOrigin(true)), "OF 5H SESSION LEFT")
    }

    // MARK: - Provider mascot mapping

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
