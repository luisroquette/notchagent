import XCTest
@testable import NotchAgent

final class ThresholdAlertsTests: XCTestCase {
    func testCrossingFiresDeepestNewThreshold() {
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 24, alreadyFired: []), 25)
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 74, alreadyFired: []), 75)
        XCTAssertEqual(ThresholdAlerts.crossed(remaining: 74), [100, 75])
    }

    func testEachThresholdFiresOncePerWindow() {
        var fired: Set<Int> = []
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 74, alreadyFired: fired), 75)
        fired.formUnion(ThresholdAlerts.crossed(remaining: 74))
        XCTAssertNil(ThresholdAlerts.newCrossing(remaining: 70, alreadyFired: fired))
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 49, alreadyFired: fired), 50)
        fired.formUnion(ThresholdAlerts.crossed(remaining: 49))
        XCTAssertEqual(ThresholdAlerts.newCrossing(remaining: 4, alreadyFired: fired), 5)
    }

    func testWindowResetRearmsAlerts() {
        XCTAssertFalse(ThresholdAlerts.shouldReset(remaining: 26, previousLow: 24), "jitter must not re-arm")
        XCTAssertTrue(ThresholdAlerts.shouldReset(remaining: 80, previousLow: 24))
    }

    /// REGRESSÃO (22/08): with no known resetsAt (Codex's estimated-session
    /// fallback), `shouldReset` fed `inferredReset`, which cleared `fired`
    /// every refresh whenever remaining stayed near 100% — the bare
    /// `remaining >= 99.5` clause fired even when `previousLow` was ALREADY
    /// at that same ~100% (no real climb happened, it's a stable plateau).
    /// Each clear re-triggered the cold-start "100% full" threshold alert,
    /// force-expanding the panel every refresh cycle (~30s) with no actual
    /// reset ever occurring — confirmed live via debug logging: 5+ identical
    /// `activeThresholdAlert` fires for Codex, threshold=100, remaining≈100,
    /// roughly 30 seconds apart.
    func testStablePlateauNearFullDoesNotReReset() {
        XCTAssertFalse(
            ThresholdAlerts.shouldReset(remaining: 99.99, previousLow: 99.99),
            "already at ~100% with no real climb since the last observation must not look like a reset"
        )
        XCTAssertFalse(
            ThresholdAlerts.shouldReset(remaining: 100, previousLow: 99.6),
            "sitting at the ceiling is not a climb — no threshold crossed since previousLow"
        )
        // A genuine climb to near-100% from a real low must still reset.
        XCTAssertTrue(ThresholdAlerts.shouldReset(remaining: 99.99, previousLow: 5))
        // No prior observation at all (guard branch) is unaffected.
        XCTAssertTrue(ThresholdAlerts.shouldReset(remaining: 99.99, previousLow: nil))
    }

    func testResetBoundaryIgnoresParserJitter() {
        let reset = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertFalse(ThresholdAlerts.resetBoundaryChanged(
            previous: reset,
            current: reset.addingTimeInterval(119)
        ))
        XCTAssertTrue(ThresholdAlerts.resetBoundaryChanged(
            previous: reset,
            current: reset.addingTimeInterval(121)
        ))
    }

    func testColdStartOnlyAnnouncesFullOrCriticalState() {
        XCTAssertEqual(ThresholdAlerts.initialCrossing(remaining: 100), 100)
        XCTAssertNil(ThresholdAlerts.initialCrossing(remaining: 87))
        XCTAssertNil(ThresholdAlerts.initialCrossing(remaining: 24))
        XCTAssertEqual(ThresholdAlerts.initialCrossing(remaining: 4), 5)
        XCTAssertNil(ThresholdAlerts.initialCrossing(remaining: 4, levels: []))
    }

    func testSeverityMapping() {
        XCTAssertEqual(ThresholdAlerts.attentionLevel(for: 100), .normal)
        XCTAssertEqual(ThresholdAlerts.attentionLevel(for: 50), .normal)
        XCTAssertEqual(ThresholdAlerts.attentionLevel(for: 25), .warning)
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
