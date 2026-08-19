import XCTest
@testable import NotchAgent

/// REGRESSÃO (commit 2325122): o headline de tokens do card foi
/// generalizado do Codex para QUALQUER provider — o Claude sem percentual
/// de sessão passou a exibir o TOTAL SEMANAL de tokens ("663.8M") como se
/// fosse a sessão corrente, no lugar do headline de percentual. O headline
/// de tokens pertence ao Codex; os demais mantêm o percentual.
final class ProviderCardHeadlineTests: XCTestCase {
    func testTokenHeadlineAllowedOnlyForCodex() {
        XCTAssertTrue(
            ProviderCardView.sessionHeadlineAllowed(for: .codex),
            "Codex keeps its session-token headline"
        )
        XCTAssertFalse(
            ProviderCardView.sessionHeadlineAllowed(for: .claudeCode),
            "Claude must keep the percentage headline"
        )
        XCTAssertFalse(
            ProviderCardView.sessionHeadlineAllowed(for: .geminiCLI),
            "Gemini must keep the percentage headline"
        )
        XCTAssertFalse(
            ProviderCardView.sessionHeadlineAllowed(for: .apiAccounts),
            "API accounts must keep the percentage headline"
        )
    }
}
