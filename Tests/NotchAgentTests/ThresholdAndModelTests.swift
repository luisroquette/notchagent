import XCTest
@testable import NotchAgent

final class ThresholdAlertsTests: XCTestCase {
    func testCrossingFiresDeepestNewThreshold() {
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 24, alreadyFired: []), 25)
        // Steep drop straight to 9%: one alert at the deepest level.
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 9, alreadyFired: []), 10)
        XCTAssertEqual(ThresholdAlerts.crossed(remaining: 9), [25, 15, 10])
    }

    func testEachThresholdFiresOncePerWindow() {
        var fired: Set<Int> = []
        // 24% → fire 25, mark.
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 24, alreadyFired: fired), 25)
        fired.formUnion(ThresholdAlerts.crossed(remaining: 24))
        // Still 22% → nothing new.
        XCTAssertNil(ThresholdAlerts.newCrossing(remaining: 22, alreadyFired: fired))
        // 14% → fire 15.
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 14, alreadyFired: fired), 15)
        fired.formUnion(ThresholdAlerts.crossed(remaining: 14))
        // 4% → fire 5 (10 also newly crossed, 5 is deeper... deepest is 5).
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 4, alreadyFired: fired), 5)
    }

    func testWindowResetRearmsAlerts() {
        XCTAssertFalse(ThresholdAlerts.shouldReset(remaining: 26), "hysteresis: jitter at the boundary must not re-arm")
        XCTAssertTrue(ThresholdAlerts.shouldReset(remaining: 80))
    }

    func testSeverityMapping() {
        XCTAssertEqual(ThresholdAlerts.attentionLevel(for: 25), .warning)
        XCTAssertEqual(ThresholdAlerts.attentionLevel(for: 15), .warning)
        XCTAssertEqual(ThresholdAlerts.attentionLevel(for: 10), .critical)
        XCTAssertEqual(ThresholdAlerts.attentionLevel(for: 5), .critical)
    }

    func testMessageSpellsOutWindow() {
        let alert = ThresholdAlert(provider: .claudeCode, threshold: 10, remaining: 8, isWeekly: false)
        XCTAssertEqual(ThresholdAlerts.message(for: alert), "Claude Code: 8% of the 5h session left")
    }
}

final class ModelBreakdownTests: XCTestCase {
    func testParserAggregatesByModel() throws {
        let url = Bundle.module.url(forResource: "claude-session", withExtension: "jsonl", subdirectory: "Fixtures")!
        let stat = try ClaudeTranscriptParser.parseFile(at: url).stat

        XCTAssertEqual(Set(stat.byModel.keys), ["claude-fable-5", "claude-sonnet-5"])
        let fable = try XCTUnwrap(stat.byModel["claude-fable-5"])
        // Two deduped fable lines: 100+10 input, 200+20 output, 1000 cacheWrite, 5300 cacheRead.
        XCTAssertEqual(fable.tokens.total, 110 + 220 + 1000 + 5300)
        XCTAssertGreaterThan(fable.costUSD, 0)
    }

    func testGaugeMetricPrefersSession() {
        let snapshot = UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: SessionUsage(usedPercent: 41),
            weekly: WeeklyUsage(usedPercent: 80)
        )
        let metric = GaugeMetric.from(snapshot)
        XCTAssertEqual(metric?.used, 41)
        XCTAssertEqual(metric?.isWeekly, false)
        XCTAssertEqual(metric?.remaining, 59)
    }
}
