import XCTest
@testable import NotchAgent

final class ClaudeParserTests: XCTestCase {
    private var fixtureURL: URL {
        Bundle.module.url(forResource: "claude-session", withExtension: "jsonl", subdirectory: "Fixtures")!
    }

    func testParsesUsageLinesAndSkipsNoise() throws {
        let stat = try ClaudeTranscriptParser.parseFile(at: fixtureURL).stat
        // 4 assistant lines with usage, minus 1 duplicate requestId = 3.
        XCTAssertEqual(stat.usageLineCount, 3)
    }

    func testAggregatesIntoHourBuckets() throws {
        let stat = try ClaudeTranscriptParser.parseFile(at: fixtureURL).stat
        XCTAssertEqual(stat.hours.count, 2)

        let hour14 = Timestamps.parseISO8601("2026-07-10T14:00:00Z")!
        let bucket = try XCTUnwrap(stat.hours[hour14])
        XCTAssertEqual(bucket.tokens.input, 150)
        XCTAssertEqual(bucket.tokens.output, 275)
        XCTAssertEqual(bucket.tokens.cacheWrite, 1000)
        XCTAssertEqual(bucket.tokens.cacheRead, 5000)
        XCTAssertEqual(bucket.messages, 2)
        XCTAssertGreaterThan(bucket.costUSD, 0)
    }

    func testTracksLastActivityAndModel() throws {
        let stat = try ClaudeTranscriptParser.parseFile(at: fixtureURL).stat
        XCTAssertEqual(stat.lastModel, "claude-fable-5")
        XCTAssertEqual(stat.lastActivity, Timestamps.parseISO8601("2026-07-10T16:10:00.000Z"))
    }

    func testMalformedLinesDoNotThrow() throws {
        XCTAssertNoThrow(try ClaudeTranscriptParser.parseFile(at: fixtureURL))
    }
}

final class SessionBlockTests: XCTestCase {
    private func hour(_ offset: Double, from base: Date) -> Date {
        base.addingTimeInterval(offset * 3600).flooredToHour
    }

    func testActiveBlockContainsNow() {
        let now = Date()
        let hours = [hour(-2, from: now), hour(-1, from: now)]
        let block = SessionBlocks.currentBlock(activityHours: hours, now: now)
        XCTAssertNotNil(block)
        XCTAssertEqual(block?.start, hour(-2, from: now))
        XCTAssertEqual(block?.end, hour(-2, from: now).addingTimeInterval(5 * 3600))
    }

    func testStaleActivityYieldsNoBlock() {
        let now = Date()
        let hours = [hour(-10, from: now), hour(-9, from: now)]
        XCTAssertNil(SessionBlocks.currentBlock(activityHours: hours, now: now))
    }

    func testNewBlockStartsAfterPreviousEnds() {
        let now = Date()
        // Old burst 12h ago, new activity 1h ago → block anchored at the new activity.
        let hours = [hour(-12, from: now), hour(-1, from: now)]
        let block = SessionBlocks.currentBlock(activityHours: hours, now: now)
        XCTAssertEqual(block?.start, hour(-1, from: now))
    }

    func testEmptyActivity() {
        XCTAssertNil(SessionBlocks.currentBlock(activityHours: [], now: Date()))
    }
}
