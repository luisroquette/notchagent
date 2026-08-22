import XCTest
@testable import NotchAgent

/// REGRESSÃO (commit 2325122): o headline de tokens do card foi
/// generalizado do Codex para QUALQUER provider — o Claude sem percentual
/// de sessão passou a exibir o TOTAL SEMANAL de tokens ("663.8M") como se
/// fosse a sessão corrente, no lugar do headline de percentual. Com o
/// LAYOUT INVARIÁVEL (20/08/2026) a regra ficou estrutural: o bloco de
/// cima é SEMPRE a sessão (percentual ou tokens da SESSÃO, nunca tokens
/// de outra janela) e o bloco de baixo é SEMPRE o semanal.
@MainActor
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

    // REGRESSÃO (21/08): com um único modelo Codex visto localmente (ex.:
    // só GPT-5.3-Codex-Spark), o card mostrava "Every model seen locally
    // this week is exhausted" — o usuário lia isso como "o Codex inteiro
    // esgotou", quando na verdade era só o cap semanal daquele modelo
    // específico (a própria OpenAI mostra outros limites de conta em 100%).
    // Com 1 único scope conhecido, o hint deve nomeá-lo.
    func testNamedQuotaHintNamesTheSingleExhaustedModel() {
        let quotas = [NamedQuota(name: "gpt-5.3-codex-spark", usedPercent: 100)]
        XCTAssertEqual(
            ProviderCardView.namedQuotaHintText(quotas: quotas, provider: .codex),
            "gpt-5.3-codex-spark's weekly cap is exhausted · check chatgpt.com/codex/settings/usage for other models"
        )
    }

    // Com 2+ modelos exauridos, a mensagem genérica continua correta — não
    // há um único nome para apontar.
    func testNamedQuotaHintStaysGenericWithMultipleExhaustedModels() {
        let quotas = [
            NamedQuota(name: "gpt-5.3-codex-spark", usedPercent: 100),
            NamedQuota(name: "gpt-5-codex", usedPercent: 99.8),
        ]
        XCTAssertEqual(
            ProviderCardView.namedQuotaHintText(quotas: quotas, provider: .codex),
            "Every model seen locally this week is exhausted · check chatgpt.com/codex/settings/usage for one that isn't"
        )
    }

    // Folga real (< 99.5% usado) em qualquer modelo conhecido cancela o
    // hint por completo — não há nada esgotado para apontar.
    func testNamedQuotaHintNilWhenAnyModelHasHeadroom() {
        let quotas = [
            NamedQuota(name: "gpt-5.3-codex-spark", usedPercent: 100),
            NamedQuota(name: "gpt-5-codex", usedPercent: 40),
        ]
        XCTAssertNil(ProviderCardView.namedQuotaHintText(quotas: quotas, provider: .codex))
    }
}
