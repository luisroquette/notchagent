import XCTest
@testable import NotchAgent

final class ClaudeQuotaProbeParseTests: XCTestCase {
    func testParsesUnifiedHeaders() {
        let headers = [
            "anthropic-ratelimit-unified-5h-utilization": "0.42",
            "anthropic-ratelimit-unified-7d-utilization": "0.87",
            "anthropic-ratelimit-unified-5h-reset": "1782408090",
            "anthropic-ratelimit-unified-7d-reset": "1782591969",
            "anthropic-ratelimit-unified-status": "allowed_warning",
            "anthropic-ratelimit-unified-representative-claim": "seven_day",
        ]
        let quota = ClaudeQuotaProbe.parse(headers: headers)
        XCTAssertEqual(quota.sessionPercent ?? -1, 42, accuracy: 0.001)
        XCTAssertEqual(quota.weeklyPercent ?? -1, 87, accuracy: 0.001)
        XCTAssertEqual(quota.sessionResetsAt, Date(timeIntervalSince1970: 1_782_408_090))
        XCTAssertEqual(quota.weeklyResetsAt, Date(timeIntervalSince1970: 1_782_591_969))
        XCTAssertEqual(quota.status, .warning)
        XCTAssertEqual(quota.limitingWindow, "seven_day")
    }

    func testToleratesPercentScaleAndClampsRange() {
        let quota = ClaudeQuotaProbe.parse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "37",
            "anthropic-ratelimit-unified-7d-utilization": "1.4",
        ])
        XCTAssertEqual(quota.sessionPercent, 37)
        XCTAssertEqual(quota.weeklyPercent!, 100, accuracy: 0.001, "0–1 scale above 1 clamps to 100")
    }

    func testRejectedStatusAndMissingHeaders() {
        let quota = ClaudeQuotaProbe.parse(headers: [
            "anthropic-ratelimit-unified-status": "rejected",
        ])
        XCTAssertEqual(quota.status, .blocked)
        XCTAssertNil(quota.sessionPercent)
        XCTAssertNil(quota.weeklyPercent)
    }

    func testCredentialsParsing() {
        let now = Date()
        let valid = """
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"r","expiresAt":\((now.timeIntervalSince1970 + 3600) * 1000)}}
        """
        XCTAssertEqual(ClaudeTokenLocator.parseCredentials(Data(valid.utf8), now: now), "sk-ant-oat01-abc")

        let expired = """
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-old","expiresAt":\((now.timeIntervalSince1970 - 60) * 1000)}}
        """
        XCTAssertNil(ClaudeTokenLocator.parseCredentials(Data(expired.utf8), now: now), "expired tokens must be rejected")
        XCTAssertNil(ClaudeTokenLocator.parseCredentials(Data("not json".utf8)))
    }
}

final class BurnRateTests: XCTestCase {
    private func samples(_ pairs: [(minutesAgo: Double, percent: Double)], now: Date) -> [PercentSample] {
        pairs.map { PercentSample(date: now.addingTimeInterval(-$0.minutesAgo * 60), percent: $0.percent) }
    }

    func testProjectsExhaustionBeforeReset() throws {
        let now = Date()
        // 20% → 50% over 60 min = 30%/h; 50 points left → ~100 min to exhaustion.
        let projection = try XCTUnwrap(BurnRate.project(
            samples: samples([(60, 20), (30, 35), (0, 50)], now: now),
            resetsAt: now.addingTimeInterval(4 * 3600),
            now: now
        ))
        XCTAssertEqual(projection.percentPerHour, 30, accuracy: 0.5)
        let exhaustsAt = try XCTUnwrap(projection.exhaustsAt)
        XCTAssertEqual(exhaustsAt.timeIntervalSince(now), 100 * 60, accuracy: 90)
    }

    func testSafeWhenExhaustionLandsAfterReset() throws {
        let now = Date()
        let projection = try XCTUnwrap(BurnRate.project(
            samples: samples([(60, 10), (0, 15)], now: now),
            resetsAt: now.addingTimeInterval(1 * 3600),
            now: now
        ))
        XCTAssertEqual(projection.percentPerHour, 5, accuracy: 0.5)
        XCTAssertNil(projection.exhaustsAt, "5%/h with 85 points left cannot exhaust within 1h")
    }

    func testFlatUsageHasNoExhaustion() throws {
        let now = Date()
        let projection = try XCTUnwrap(BurnRate.project(
            samples: samples([(60, 40), (0, 40)], now: now),
            resetsAt: nil,
            now: now
        ))
        XCTAssertNil(projection.exhaustsAt)
        XCTAssertEqual(projection.percentPerHour, 0)
    }

    func testWindowResetDropIsIgnored() throws {
        let now = Date()
        // 80% → reset → 5% → 20%: only the post-reset tail counts.
        let projection = try XCTUnwrap(BurnRate.project(
            samples: samples([(80, 78), (70, 80), (30, 5), (0, 20)], now: now),
            resetsAt: now.addingTimeInterval(5 * 3600),
            now: now
        ))
        XCTAssertEqual(projection.percentPerHour, 30, accuracy: 1)
    }

    func testInsufficientSamples() {
        let now = Date()
        XCTAssertNil(BurnRate.project(samples: [], resetsAt: nil, now: now))
        XCTAssertNil(BurnRate.project(
            samples: [PercentSample(date: now, percent: 10)], resetsAt: nil, now: now
        ))
    }

    func testVerdictStrings() {
        XCTAssertNil(BurnRate.verdict(nil))
        XCTAssertNil(BurnRate.verdict(BurnRate.Projection(percentPerHour: 0, exhaustsAt: nil)))
        let safe = BurnRate.verdict(BurnRate.Projection(percentPerHour: 8, exhaustsAt: nil))
        XCTAssertEqual(safe, "+8%/h · safe until reset")
        let now = Date()
        let doomed = BurnRate.verdict(
            BurnRate.Projection(percentPerHour: 30, exhaustsAt: now.addingTimeInterval(92 * 60)),
            now: now
        )
        XCTAssertTrue(doomed?.contains("runs out") ?? false)
        XCTAssertTrue(doomed?.contains("1h 32m") ?? false)
    }
}

final class CodexWindowClassificationTests: XCTestCase {
    func testClassicPrimarySessionSecondaryWeekly() {
        let info = CodexTokenInfo(
            timestamp: nil,
            totals: .zero,
            primary: CodexRateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil),
            secondary: CodexRateWindow(usedPercent: 60, windowMinutes: 10080, resetsAt: nil)
        )
        XCTAssertEqual(info.sessionWindow?.usedPercent, 10)
        XCTAssertEqual(info.weeklyWindow?.usedPercent, 60)
    }

    func testSparkPlanWeeklyOnlyPrimary() {
        // Real shape observed on GPT-5.3-Codex-Spark: primary IS the weekly window.
        let info = CodexTokenInfo(
            timestamp: nil,
            totals: .zero,
            primary: CodexRateWindow(usedPercent: 44, windowMinutes: 10080, resetsAt: nil),
            secondary: nil,
            limitName: "GPT-5.3-Codex-Spark"
        )
        XCTAssertNil(info.sessionWindow, "weekly-only plans must not fake a session percent")
        XCTAssertEqual(info.weeklyWindow?.usedPercent, 44)
    }
}

final class AppSettingsCompatibilityTests: XCTestCase {
    func testDecodingOldSettingsAppliesNewDefaults() throws {
        // Persisted blob from a build that predates the quota probe flag.
        let old = """
        {"refreshIntervalSeconds":120,"warningThresholdPercent":60,"criticalThresholdPercent":85,"notchOverlayEnabled":false,"fallbackPillEnabled":true}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.refreshIntervalSeconds, 120)
        XCTAssertEqual(settings.warningThresholdPercent, 60)
        XCTAssertFalse(settings.notchOverlayEnabled)
        XCTAssertTrue(settings.claudeQuotaProbeEnabled, "new fields default sanely")
        XCTAssertNil(settings.claudeSessionTokenBudget)
    }
}
