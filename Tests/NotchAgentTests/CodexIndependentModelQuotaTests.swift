import XCTest
@testable import NotchAgent

final class CodexQuotaIdentityTests: XCTestCase {
    func testModelNameNeverDefinesQuotaIdentity() {
        let info = CodexTokenInfo(timestamp: nil, totals: .zero, model: "gpt-5.6-luna")
        XCTAssertEqual(CodexProvider.quotaKey(for: info), "codex")
    }

    func testSparkUsesOfficialSeparateLimitID() {
        let info = CodexTokenInfo(
            timestamp: nil,
            totals: .zero,
            limitID: "codex_bengalfox",
            limitName: "GPT-5.3-Codex-Spark",
            model: "gpt-5.6-sol"
        )
        XCTAssertEqual(CodexProvider.quotaKey(for: info), "codex_bengalfox")
        XCTAssertEqual(CodexProvider.quotaName(for: info, key: "codex_bengalfox"), "GPT-5.3-Codex-Spark")
    }
}
