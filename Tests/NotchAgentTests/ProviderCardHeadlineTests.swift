import XCTest
@testable import NotchAgent

/// REGRESSÃO (commit 2325122): o headline de tokens do card foi
/// generalizado do Codex para QUALQUER provider — o Claude sem percentual
/// de sessão passou a exibir o TOTAL SEMANAL de tokens ("663.8M") como se
/// fosse a sessão corrente, no lugar do headline de percentual. Com o
/// LAYOUT INVARIÁVEL (20/08/2026) a regra ficou estrutural: o bloco de
/// cima é SEMPRE a sessão (percentual ou tokens da SESSÃO, nunca tokens
/// de outra janela) e o bloco de baixo é SEMPRE o semanal.
final class ProviderCardHeadlineTests: XCTestCase {
    // REGRESSÃO: probe ligado sem credencial OAuth → sem quota → o card
    // exibia tokens como se fossem a cota. Deve declarar indisponibilidade.
    func testQuotaUnavailableOnlyWhenProbeOnAndNoQuota() {
        XCTAssertTrue(
            ProviderCardView.quotaUnavailable(for: .claudeCode, probeEnabled: true, hasQuota: false),
            "probe on + no quota = unavailable"
        )
        XCTAssertFalse(
            ProviderCardView.quotaUnavailable(for: .claudeCode, probeEnabled: true, hasQuota: true),
            "with quota the percent renders normally"
        )
        XCTAssertFalse(
            ProviderCardView.quotaUnavailable(for: .claudeCode, probeEnabled: false, hasQuota: false),
            "probe off keeps the token fallback (user chose not to connect)"
        )
        XCTAssertFalse(
            ProviderCardView.quotaUnavailable(for: .codex, probeEnabled: true, hasQuota: false),
            "Codex never shows the Claude login hint"
        )
    }
}
