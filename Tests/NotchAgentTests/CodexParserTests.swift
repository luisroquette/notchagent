import XCTest
@testable import NotchAgent

final class CodexParserTests: XCTestCase {
    private var fixtureURL: URL {
        Bundle.module.url(forResource: "codex-rollout", withExtension: "jsonl", subdirectory: "Fixtures")!
    }

    func testPicksLatestTokenCountEvent() throws {
        let info = try XCTUnwrap(CodexRolloutParser.latestTokenInfo(at: fixtureURL))
        XCTAssertEqual(info.primary?.usedPercent, 10.0)
        XCTAssertEqual(info.secondary?.usedPercent, 19.0)
        XCTAssertEqual(info.planType, "prolite")
        XCTAssertEqual(info.limitID, "codex")
    }

    func testNormalizesCachedInputTokens() throws {
        let info = try XCTUnwrap(CodexRolloutParser.latestTokenInfo(at: fixtureURL))
        // input 16621 with 4480 cached → 12141 fresh input + 4480 cache reads.
        XCTAssertEqual(info.totals.input, 12141)
        XCTAssertEqual(info.totals.cacheRead, 4480)
        XCTAssertEqual(info.totals.output, 398)
        XCTAssertEqual(info.totals.total, 12141 + 4480 + 398)
    }

    func testParsesResetTimestamps() throws {
        let info = try XCTUnwrap(CodexRolloutParser.latestTokenInfo(at: fixtureURL))
        XCTAssertEqual(info.primary?.resetsAt, Date(timeIntervalSince1970: 1_782_408_090))
        XCTAssertEqual(info.secondary?.resetsAt, Date(timeIntervalSince1970: 1_782_591_969))
        XCTAssertEqual(info.primary?.windowMinutes, 300)
        XCTAssertEqual(info.secondary?.windowMinutes, 10080)
    }

    func testExtractsModelFromTurnContext() throws {
        let info = try XCTUnwrap(CodexRolloutParser.latestTokenInfo(at: fixtureURL))
        XCTAssertEqual(info.model, "gpt-5.1-codex")
    }

    func testFileWithoutTokenCountReturnsNil() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).jsonl")
        try Data("{\"type\":\"session_meta\",\"payload\":{}}\n".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertNil(try CodexRolloutParser.latestTokenInfo(at: tmp))
    }
}

final class CodexAppServerRateLimitReaderTests: XCTestCase {
    func testOfficialLimitsRemainAvailableWithoutLocalRollouts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions")
        let executable = root.appendingPathComponent("fake-codex")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let response = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":21,"windowDurationMins":300},"secondary":{"usedPercent":69,"windowDurationMins":10080}}}}"#
        try Data("#!/bin/sh\nprintf '%s\\n' '\(response)'\nsleep 1\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let reader = CodexAppServerRateLimitReader(executableURL: executable, minInterval: 0)
        let snapshot = try await CodexProvider(root: sessions, appServerRateLimits: reader)
            .fetchSnapshot(settings: AppSettings())

        XCTAssertEqual(snapshot.health, .ok)
        XCTAssertEqual(snapshot.session?.tokens, .zero)
        XCTAssertEqual(snapshot.session?.usedPercent, 21)
        XCTAssertEqual(snapshot.weekly?.usedPercent, 69)
    }

    func testLiveOfficialRateLimitsWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NOTCHAGENT_CODEX_RATE_LIMIT_E2E"] == "1" else {
            throw XCTSkip("Set NOTCHAGENT_CODEX_RATE_LIMIT_E2E=1 for the authenticated read-only test")
        }
        let reader = CodexAppServerRateLimitReader(minInterval: 0)
        let response = await reader.currentLimits()
        let limits = try XCTUnwrap(response)
        XCTAssertNotNil(limits["codex"]?.weeklyWindow)
        XCTAssertNotNil(limits["codex_bengalfox"]?.sessionWindow)
    }

    func testParsesOfficialSharedAndSparkBuckets() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let response = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1800000300},"secondary":{"usedPercent":67,"windowDurationMins":10080,"resetsAt":1800604800}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1800000300},"secondary":{"usedPercent":67,"windowDurationMins":10080,"resetsAt":1800604800},"planType":"pro"},"codex_bengalfox":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":3,"windowDurationMins":300,"resetsAt":1800000600},"secondary":{"usedPercent":9,"windowDurationMins":10080,"resetsAt":1800608400},"planType":"pro"}}}}"#

        let limits = try XCTUnwrap(
            CodexAppServerRateLimitReader.parseResponse(Data((response + "\n").utf8), now: now)
        )
        XCTAssertEqual(limits["codex"]?.sessionWindow?.usedPercent, 12)
        XCTAssertEqual(limits["codex"]?.weeklyWindow?.usedPercent, 67)
        XCTAssertEqual(limits["codex_bengalfox"]?.sessionWindow?.usedPercent, 3)
        XCTAssertEqual(limits["codex_bengalfox"]?.weeklyWindow?.usedPercent, 9)
        XCTAssertEqual(limits["codex_bengalfox"]?.limitName, "GPT-5.3-Codex-Spark")
    }

    func testParsesRateLimitResetCredits() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let response = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":100,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":3,"credits":[{"status":"available","expiresAt":1800604800},{"status":"available","expiresAt":1800100000},{"status":"used","expiresAt":1800000001}]}}}"#

        let limits = try XCTUnwrap(CodexAppServerRateLimitReader.parseResponse(Data(response.utf8), now: now))
        let credits = try XCTUnwrap(limits["codex"]?.resetCredits)
        XCTAssertEqual(credits.availableCount, 3)
        // totalCount counts EVERY credit ever granted, used ones included.
        XCTAssertEqual(credits.totalCount, 3)
        // Soonest AVAILABLE expiry — the already-used one must not win the min().
        XCTAssertEqual(credits.soonestExpiresAt, Date(timeIntervalSince1970: 1800100000))
    }

    func testTotalCountIncludesUsedCredits() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let response = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":50,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":1,"credits":[{"status":"available","expiresAt":1800604800},{"status":"used","expiresAt":1800000001},{"status":"used","expiresAt":1800000002}]}}}"#

        let limits = try XCTUnwrap(CodexAppServerRateLimitReader.parseResponse(Data(response.utf8), now: now))
        let credits = try XCTUnwrap(limits["codex"]?.resetCredits)
        XCTAssertEqual(credits.availableCount, 1)
        XCTAssertEqual(credits.totalCount, 3)
    }

    func testFallsBackToBackwardCompatibleSingleBucket() throws {
        let response = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":1800000300},"secondary":null}}}"#
        let limits = try XCTUnwrap(CodexAppServerRateLimitReader.parseResponse(Data(response.utf8)))
        XCTAssertEqual(limits.keys.sorted(), ["codex"])
        XCTAssertEqual(limits["codex"]?.sessionWindow?.usedPercent, 40)
    }

    /// REGRESSÃO 16/09/2026: NotchAgent rodou 60h sem reiniciar; o app-server
    /// oficial parou de responder com sucesso em algum ponto e o notch continuou
    /// exibindo "81% restante" com confiança total enquanto a conta real já
    /// estava em 100% usado / 0% restante. `cached` não tinha teto de idade.
    func testCacheExpiresAfterMaxAgeWhenFetchesKeepFailing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable = root.appendingPathComponent("fake-codex")
        let marker = root.appendingPathComponent("called")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let response = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":19,"windowDurationMins":10080}}}}"#
        let script = """
        #!/bin/sh
        if [ -f "\(marker.path)" ]; then
            exit 1
        fi
        touch "\(marker.path)"
        printf '%s\\n' '\(response)'
        sleep 1
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let reader = CodexAppServerRateLimitReader(executableURL: executable, minInterval: 0, maxCacheAge: 300)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        let first = await reader.currentLimits(now: t0)
        XCTAssertEqual(first?["codex"]?.weeklyWindow?.usedPercent, 19)

        // Fetch fails silently but the cache is still fresh: brief hiccups are tolerated.
        let stillFresh = await reader.currentLimits(now: t0.addingTimeInterval(60))
        XCTAssertEqual(stillFresh?["codex"]?.weeklyWindow?.usedPercent, 19)

        // Fetches kept failing past maxCacheAge: the stale reading must be dropped,
        // never frozen indefinitely regardless of how long the process has been up.
        let stale = await reader.currentLimits(now: t0.addingTimeInterval(601))
        XCTAssertNil(stale)
    }
}

final class GeminiParserTests: XCTestCase {
    private var fixtureURL: URL {
        Bundle.module.url(forResource: "gemini-logs", withExtension: "json", subdirectory: "Fixtures")!
    }

    func testCountsPromptsAndSessions() throws {
        let stat = try GeminiLogParser.parseLogFile(at: fixtureURL)
        XCTAssertEqual(stat.promptTimestamps.count, 3)
        XCTAssertEqual(stat.sessionIDs, ["s1", "s2"])
        XCTAssertEqual(stat.lastActivity, Timestamps.parseISO8601("2026-07-11T09:00:00.000Z"))
    }
}
