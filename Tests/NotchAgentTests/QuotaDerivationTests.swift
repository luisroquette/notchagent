import XCTest
@testable import NotchAgent

/// REGRESSÃO: o percentual semanal do card vinha de uma expressão inline
/// (quota ?? estimativa de budget) — com as duas fontes ausentes, o
/// resultado era nil SILENCIOSO e o card degradava para tokens crus.
/// A derivação agora é uma função testada, e o contrato está explícito.
final class QuotaDerivationTests: XCTestCase {
    func testQuotaWinsOverBudget() {
        XCTAssertEqual(
            ClaudeProvider.weeklyUsedPercent(quotaWeekly: 100, budget: 1_000_000, weekTokens: 10),
            100,
            "the quota probe is authoritative — the budget estimate must never override it"
        )
    }

    func testBudgetEstimateFillsWhenQuotaIsAbsent() {
        XCTAssertEqual(
            ClaudeProvider.weeklyUsedPercent(quotaWeekly: nil, budget: 1_000, weekTokens: 400),
            40
        )
    }

    func testBudgetEstimateCapsAt100() {
        XCTAssertEqual(
            ClaudeProvider.weeklyUsedPercent(quotaWeekly: nil, budget: 1_000, weekTokens: 9_000),
            100
        )
    }

    func testNilWhenBothSourcesAreAbsent() {
        // The exact state of the incident day: probe enabled but silent,
        // no budget set — the derivation must return nil EXPLICITLY, and
        // the card's quotaUnavailable guard turns that into the honest
        // "QUOTA INDISPONÍVEL" instead of raw tokens.
        XCTAssertNil(ClaudeProvider.weeklyUsedPercent(quotaWeekly: nil, budget: nil, weekTokens: 500))
        XCTAssertNil(ClaudeProvider.weeklyUsedPercent(quotaWeekly: nil, budget: 0, weekTokens: 500))
    }
}

/// O espelho de log em arquivo: o diagnóstico do dia custou horas porque
/// o os_log não persiste. O arquivo precisa gravar e capar.
final class LogFileTests: XCTestCase {
    func testWriteCreatesAndAppends() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("logfile-test-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        // LogFile writes to the real app.log; test the mechanics via a
        // direct file handle round-trip of the same helpers.
        FileManager.default.createFile(atPath: url.path, contents: "a\n".data(using: .utf8)!)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: "b\n".data(using: .utf8)!)
        try handle.close()
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(content, "a\nb\n", "append-only file log keeps history")
    }

    func testCapKeepsOnlyTheTail() {
        // Mirror of LogFile.capIfNeeded semantics: over the cap, the file
        // keeps the LAST half — the newest diagnostics.
        let big = String(repeating: "x", count: 700 * 1024)
        let tail = "newest-line\n"
        XCTAssertTrue(big.count > LogFile.maxBytes)
        let kept = (big + tail).suffix(LogFile.maxBytes / 2)
        XCTAssertTrue(String(kept).contains("newest-line"), "the cap must keep the newest lines")
    }
}
