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

    func testToleratesPercentScaleWithoutFalseCritical() {
        let quota = ClaudeQuotaProbe.parse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "37",
            "anthropic-ratelimit-unified-7d-utilization": "1.4",
        ])
        XCTAssertEqual(quota.sessionPercent, 37)
        // Ambiguous scale (could be 140% overage on 0–1, or 1.4% on 0–100):
        // err toward understating — never fabricate a 100% that fires alerts.
        XCTAssertEqual(quota.weeklyPercent!, 1.4, accuracy: 0.001)
        XCTAssertEqual(ClaudeQuotaProbe.parse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "1.0",
        ]).sessionPercent, 100)
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

    #if os(macOS)
    func testUsagePortalParsesRemainingPercentAndResetDurations() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = try XCTUnwrap(AnthropicUsageQuotaReader.parseUsageText("""
        CLAUDE
        93%
        OF 5H SESSION LEFT
        RESETS • 13:40
        4h 45m
        CODEX
        88%
        OF WEEKLY LIMIT LEFT
        RESETS • 17:02
        5d 8h
        """, now: now))

        XCTAssertEqual(quota.sessionPercent, 7)
        XCTAssertEqual(quota.weeklyPercent, 12)
        XCTAssertEqual(try XCTUnwrap(quota.sessionResetsAt).timeIntervalSince(now), 17_100, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(quota.weeklyResetsAt).timeIntervalSince(now), 460_800, accuracy: 1)
        XCTAssertEqual(quota.status, .ok)
        XCTAssertEqual(quota.limitingWindow, "seven_day")
    }

    func testUsagePortalParsesCurrentPortugueseUsedPercentFormat() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = try XCTUnwrap(AnthropicUsageQuotaReader.parseUsageText("""
        Seus limites de uso Equipe
        Sessão atual
        Reinicia em 4 h 48 min
        12% usado
        Limites semanais
        Seus limites estão temporariamente aumentados.
        Todos os modelos
        Reinicia dom., 02:59
        47% usado
        Fable
        Você ainda não usou Fable
        0% usado
        """, now: now))

        XCTAssertEqual(quota.sessionPercent, 12)
        XCTAssertEqual(quota.weeklyPercent, 47)
        XCTAssertEqual(try XCTUnwrap(quota.sessionResetsAt).timeIntervalSince(now), 17_280, accuracy: 1)
        XCTAssertEqual(quota.status, .ok)
        XCTAssertEqual(quota.limitingWindow, "seven_day")
    }
    #endif
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

final class CodexWeeklyScopeMergeTests: XCTestCase {
    private func entry(
        model: String?,
        usedPercent: Double,
        resetsAt: Date,
        timestamp: Date,
        start: Date
    ) -> (info: CodexTokenInfo, start: Date) {
        var info = CodexTokenInfo(
            timestamp: timestamp,
            totals: .zero,
            primary: CodexRateWindow(usedPercent: usedPercent, windowMinutes: 10_080, resetsAt: resetsAt)
        )
        info.model = model
        return (info: info, start: start)
    }

    /// Two different models must both survive even when they come from
    /// different files at different times.
    func testRecoversEachModelsOwnScope() {
        let now = Date()
        let exhausted = entry(
            model: "gpt-5.6-sol", usedPercent: 100, resetsAt: now.addingTimeInterval(5 * 86_400),
            timestamp: now.addingTimeInterval(-6 * 3600), start: now.addingTimeInterval(-6 * 3600)
        )
        let other = entry(
            model: "gpt-5.3-codex-spark", usedPercent: 8, resetsAt: now.addingTimeInterval(7 * 86_400),
            timestamp: now, start: now
        )
        let scopes = CodexProvider.freshestWeeklyScopesByModel([exhausted, other])
        XCTAssertEqual(scopes.count, 2)
        XCTAssertEqual(scopes["gpt-5.6-sol"]?.window.usedPercent, 100)
        XCTAssertEqual(scopes["gpt-5.3-codex-spark"]?.window.usedPercent, 8)
    }

    /// Reproduces the exact bug reported 15/08/2026: `resetsAt` is
    /// recomputed fresh on every response (drifts by mere seconds between
    /// sightings of the SAME model's cap) — keying by it fragmented one real
    /// scope into dozens of fake ones. Two sightings of the same model with
    /// different `resetsAt` must collapse into ONE scope, keeping only the
    /// freshest observation.
    func testSameModelWithDriftingResetsAtCollapsesToOneScope() {
        let now = Date()
        let older = entry(
            model: "gpt-5.6-sol", usedPercent: 40, resetsAt: now.addingTimeInterval(86_400),
            timestamp: now.addingTimeInterval(-3600), start: now.addingTimeInterval(-3600)
        )
        let newer = entry(
            model: "gpt-5.6-sol", usedPercent: 55, resetsAt: now.addingTimeInterval(86_401), // 1s drift
            timestamp: now, start: now
        )
        let scopes = CodexProvider.freshestWeeklyScopesByModel([older, newer])
        XCTAssertEqual(scopes.count, 1, "the same model must never fragment into multiple scopes just because resetsAt drifted")
        XCTAssertEqual(scopes["gpt-5.6-sol"]?.window.usedPercent, 55, "the freshest sighting must win, not the first one seen")
    }

    func testEntryWithNoKnownModelIsSkipped() {
        let now = Date()
        let unknown = entry(model: nil, usedPercent: 10, resetsAt: now.addingTimeInterval(86_400), timestamp: now, start: now)
        XCTAssertTrue(CodexProvider.freshestWeeklyScopesByModel([unknown]).isEmpty, "an event with no model attached can't be honestly labeled, so it's skipped rather than guessed at")
    }
}

final class ClaudeFableQuotaRoutingTests: XCTestCase {
    /// Fable 5 is metered separately from the shared Haiku/Sonnet/Opus pool —
    /// its headers must route to its own cache, never overwrite the main one.
    func testFableModelRoutesToItsOwnCache() {
        XCTAssertTrue(ClaudeQuotaProbe.isFableModel("claude-fable-5"))
        XCTAssertFalse(ClaudeQuotaProbe.isFableModel("claude-sonnet-5"))
        XCTAssertFalse(ClaudeQuotaProbe.isFableModel("claude-opus-4-8"))
        XCTAssertFalse(ClaudeQuotaProbe.isFableModel("claude-haiku-4-5-20251001"))
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
        XCTAssertFalse(settings.claudeQuotaProbeEnabled, "network quota probing must remain explicit opt-in")
        XCTAssertFalse(settings.notchAgentDeskOnboardingCompleted)
        XCTAssertNil(settings.claudeSessionTokenBudget)
    }

    func testLegacyNetworkProbeIsDisabledUntilNewConsent() throws {
        let legacy = """
        {"claudeQuotaProbeEnabled":true,"notchAgentDeskEnabled":true}
        """
        let migrated = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertFalse(migrated.claudeQuotaProbeEnabled)
        XCTAssertTrue(migrated.notchAgentDeskOnboardingCompleted)

        var consented = AppSettings()
        consented.claudeQuotaProbeConsentVersion = 1
        consented.claudeQuotaProbeEnabled = true
        let restored = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(consented)
        )
        XCTAssertTrue(restored.claudeQuotaProbeEnabled)
    }
}
