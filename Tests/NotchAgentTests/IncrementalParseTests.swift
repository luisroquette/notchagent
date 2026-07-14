import XCTest
@testable import NotchAgent

/// REGRESSÃO: transcripts ativos de 100+ MB eram re-parseados inteiros a cada
/// refresh (o primeiro tick nunca terminava com 465 MB na janela). O parse
/// agora é incremental por offset com pré-filtro de bytes.
final class IncrementalParseTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("incremental-\(UUID().uuidString).jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func usageLine(id: String, timestamp: String, input: Int, output: Int) -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"\(id)","message":{"id":"m_\(id)","model":"claude-fable-5","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
        """
    }

    func testIncrementalParseMatchesFullParse() throws {
        let line1 = usageLine(id: "a", timestamp: "2026-07-10T10:00:00.000Z", input: 100, output: 200)
        let line2 = usageLine(id: "b", timestamp: "2026-07-10T11:00:00.000Z", input: 50, output: 75)
        try Data((line1 + "\n").utf8).write(to: fileURL)

        let first = try ClaudeTranscriptParser.parseFile(at: fileURL)
        XCTAssertEqual(first.stat.usageLineCount, 1)

        // Append: incremental parse from the stored offset must see only the new line.
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line2 + "\n").utf8))
        try handle.close()

        let incremental = try ClaudeTranscriptParser.parseFile(
            at: fileURL, from: first.consumed, into: first.stat
        )
        let full = try ClaudeTranscriptParser.parseFile(at: fileURL)

        XCTAssertEqual(incremental.stat.usageLineCount, full.stat.usageLineCount)
        XCTAssertEqual(incremental.stat.hours.count, full.stat.hours.count)
        XCTAssertEqual(incremental.consumed, full.consumed)
        let totalIncremental = incremental.stat.hours.values.reduce(0) { $0 + $1.tokens.total }
        let totalFull = full.stat.hours.values.reduce(0) { $0 + $1.tokens.total }
        XCTAssertEqual(totalIncremental, totalFull)
    }

    func testDedupSurvivesIncrementalReparse() throws {
        let line1 = usageLine(id: "a", timestamp: "2026-07-10T10:00:00.000Z", input: 100, output: 200)
        try Data((line1 + "\n").utf8).write(to: fileURL)
        let first = try ClaudeTranscriptParser.parseFile(at: fileURL)

        // The same requestId appended later (retry) must not double count.
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line1 + "\n").utf8))
        try handle.close()

        let incremental = try ClaudeTranscriptParser.parseFile(
            at: fileURL, from: first.consumed, into: first.stat
        )
        XCTAssertEqual(incremental.stat.usageLineCount, 1)
    }

    func testTrailingPartialLineIsNotConsumed() throws {
        let complete = usageLine(id: "a", timestamp: "2026-07-10T10:00:00.000Z", input: 10, output: 20)
        let partial = "{\"type\":\"assistant\",\"timest"
        try Data((complete + "\n" + partial).utf8).write(to: fileURL)

        let result = try ClaudeTranscriptParser.parseFile(at: fileURL)
        XCTAssertEqual(result.stat.usageLineCount, 1)
        XCTAssertEqual(
            Int(result.consumed), (complete + "\n").utf8.count,
            "partial trailing line must remain unconsumed for the next incremental pass"
        )
    }

    func testQuickMatchFiltersNonUsageLines() {
        let huge = Data("{\"type\":\"user\",\"content\":\"\(String(repeating: "x", count: 10_000))\"}".utf8)
        XCTAssertFalse(ClaudeTranscriptParser.quickMatch(huge))
        let usage = Data(usageLine(id: "z", timestamp: "2026-07-10T10:00:00Z", input: 1, output: 1).utf8)
        XCTAssertTrue(ClaudeTranscriptParser.quickMatch(usage))
    }

    func testScanCacheIncrementalFlow() async throws {
        let cache = ClaudeScanCache()
        let line1 = usageLine(id: "a", timestamp: "2026-07-10T10:00:00.000Z", input: 100, output: 200)
        try Data((line1 + "\n").utf8).write(to: fileURL)

        let stat1 = try await cache.stat(for: fileURL)
        XCTAssertEqual(stat1?.usageLineCount, 1)

        let line2 = usageLine(id: "b", timestamp: "2026-07-10T12:00:00.000Z", input: 5, output: 5)
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line2 + "\n").utf8))
        try handle.close()

        let stat2 = try await cache.stat(for: fileURL)
        XCTAssertEqual(stat2?.usageLineCount, 2)

        // Truncation forces a clean full re-parse.
        try Data((line2 + "\n").utf8).write(to: fileURL)
        let stat3 = try await cache.stat(for: fileURL)
        XCTAssertEqual(stat3?.usageLineCount, 1)
    }
}
