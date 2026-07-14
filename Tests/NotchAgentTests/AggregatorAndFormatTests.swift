import XCTest
@testable import NotchAgent

final class StatusAggregatorTests: XCTestCase {
    private var settings = AppSettings()

    private func snapshot(_ provider: ProviderID, sessionPercent: Double?, health: ProviderHealth = .ok) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            health: health,
            session: SessionUsage(usedPercent: sessionPercent),
            lastActivityAt: Date()
        )
    }

    func testAttentionThresholds() {
        XCTAssertEqual(StatusAggregator.attention(for: snapshot(.codex, sessionPercent: 10), settings: settings), .normal)
        XCTAssertEqual(StatusAggregator.attention(for: snapshot(.codex, sessionPercent: 75), settings: settings), .warning)
        XCTAssertEqual(StatusAggregator.attention(for: snapshot(.codex, sessionPercent: 95), settings: settings), .critical)
    }

    func testDegradedHealthIsAtLeastWarning() {
        XCTAssertEqual(
            StatusAggregator.attention(for: snapshot(.claudeCode, sessionPercent: nil, health: .parseError), settings: settings),
            .warning
        )
    }

    func testOverallAttentionIsWorstCase() {
        let snapshots: [ProviderID: UsageSnapshot] = [
            .codex: snapshot(.codex, sessionPercent: 95),
            .claudeCode: snapshot(.claudeCode, sessionPercent: 10),
        ]
        XCTAssertEqual(StatusAggregator.overallAttention(snapshots: snapshots, settings: settings), .critical)
    }

    func testFavoriteProviderWins() {
        var settings = AppSettings()
        settings.favoriteProvider = .codex
        let snapshots: [ProviderID: UsageSnapshot] = [
            .codex: snapshot(.codex, sessionPercent: 5),
            .claudeCode: snapshot(.claudeCode, sessionPercent: 50),
        ]
        XCTAssertEqual(StatusAggregator.primaryProvider(snapshots: snapshots, settings: settings), .codex)
    }

    func testPrimaryFallsBackToMostRecentActivity() {
        var old = snapshot(.geminiCLI, sessionPercent: nil)
        old.lastActivityAt = Date().addingTimeInterval(-9999)
        let fresh = snapshot(.claudeCode, sessionPercent: nil)
        let snapshots: [ProviderID: UsageSnapshot] = [.geminiCLI: old, .claudeCode: fresh]
        XCTAssertEqual(StatusAggregator.primaryProvider(snapshots: snapshots, settings: settings), .claudeCode)
    }

    func testTransitionAlertOnlyFiresOnWorsening() {
        let before: [ProviderID: UsageSnapshot] = [.codex: snapshot(.codex, sessionPercent: 10)]
        let worse = snapshot(.codex, sessionPercent: 92)
        let alerts = StatusAggregator.transitionAlerts(old: before, new: worse, settings: settings)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.level, .critical)

        let calm = snapshot(.codex, sessionPercent: 5)
        let after: [ProviderID: UsageSnapshot] = [.codex: worse]
        XCTAssertTrue(StatusAggregator.transitionAlerts(old: after, new: calm, settings: settings).isEmpty)
    }
}

final class PricingTests: XCTestCase {
    func testPrefixMatching() {
        XCTAssertNotNil(PricingTable.pricing(forModel: "claude-fable-5"))
        XCTAssertNotNil(PricingTable.pricing(forModel: "gpt-5"))
        XCTAssertNil(PricingTable.pricing(forModel: "totally-unknown-model"))
    }

    func testClaudeCostMath() {
        // 1M of everything on sonnet: 3 + 15 + 3.75 + 0.3 = 22.05
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000)
        XCTAssertEqual(PricingTable.costUSD(model: "claude-sonnet-5", usage: usage), 22.05, accuracy: 0.001)
    }

    func testUnknownModelCostsZero() {
        let usage = TokenUsage(input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0)
        XCTAssertEqual(PricingTable.costUSD(model: "mystery", usage: usage), 0)
    }
}

final class FormatTests: XCTestCase {
    func testTokenFormatting() {
        XCTAssertEqual(Format.tokens(950), "950")
        XCTAssertEqual(Format.tokens(12_400), "12.4k")
        XCTAssertEqual(Format.tokens(3_400_000), "3.4M")
        XCTAssertEqual(Format.tokens(2_000_000), "2M")
    }

    func testCountdown() {
        let reference = Date()
        XCTAssertEqual(Format.countdown(to: reference.addingTimeInterval(-10), from: reference), "now")
        XCTAssertEqual(Format.countdown(to: reference.addingTimeInterval(134 * 60), from: reference), "2h 14m")
        XCTAssertEqual(Format.countdown(to: reference.addingTimeInterval(45 * 60), from: reference), "45m")
    }

    func testHourFlooring() {
        let date = Timestamps.parseISO8601("2026-07-10T14:59:59.999Z")!
        XCTAssertEqual(date.flooredToHour, Timestamps.parseISO8601("2026-07-10T14:00:00Z"))
    }
}

final class GeometryTests: XCTestCase {
    func testPanelFrameIsTopCentered() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let canvas = CGSize(width: 720, height: 460)
        let frame = NotchGeometry.panelFrame(canvas: canvas, screenFrame: screen)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.size, CGSize(width: 720, height: 460))
    }

    func testPanelFrameOnSecondaryScreenOrigin() {
        // Screens left of the main one have negative origins in AppKit space.
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let frame = NotchGeometry.panelFrame(canvas: CGSize(width: 700, height: 400), screenFrame: screen)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, screen.maxY)
    }

    @MainActor
    func testViewModelInteractiveRectTracksMode() {
        let vm = NotchViewModel(geometry: NotchGeometry(
            hasNotch: true, notchWidth: 200, topInset: 38,
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        ))
        let compact = vm.interactiveRect
        XCTAssertEqual(compact.height, 38)
        XCTAssertEqual(compact.width, 200 + 300)
        XCTAssertEqual(compact.midX, NotchViewModel.canvasSize.width / 2, accuracy: 0.5)

        vm.togglePin()
        let expanded = vm.interactiveRect
        XCTAssertTrue(vm.isExpanded)
        XCTAssertGreaterThan(expanded.height, compact.height)
    }
}
