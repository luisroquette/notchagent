import XCTest
@testable import NotchAgent

/// CONTRATO INVARIÁVEL — a hierarquia das janelas de quota:
///
///     BLOCKED (API) > weekly exausto > sessão (5h) > weekly parcial
///
/// A janela de 5h é SUBORDINADA à semanal; um bloqueio da API vence tudo.
/// Já houve DUAS regressões por violação desse contrato (19/08: sessão
/// oficial mascarando semanal exausto; 20/08: painel BURN lendo o
/// percentual cru da sessão com a conta BLOCKED).
///
/// Estes testes LÊEM O CÓDIGO-FONTE e exigem a ORDEM FÍSICA das checagens
/// e o consumo exclusivo do gauge pelas views. Não dá para um refactor
/// futuro "passar" reescrevendo comentário ou afrouxando um assert de
/// teste funcional sem quebrar aqui — este arquivo é o guard estrutural.
final class QuotaHierarchyContractTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // QuotaHierarchyContractTests.swift
            .deletingLastPathComponent() // NotchAgentTests
            .deletingLastPathComponent() // Tests
    }

    private func source(_ path: String) -> String {
        let url = repoRoot.appendingPathComponent(path)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("fonte não encontrado: \(path)")
            return ""
        }
        return content
    }

    /// 1. O gauge é o ÚNICO ponto que decide qual janela aparece.
    /// A ordem física no `GaugeMetric.from` DEVE ser:
    /// blocked → weeklyExhausted → session → weekly fallback.
    func testGaugeMetricFromChecksWeeklyExhaustionBeforeSession() {
        let source = source("Sources/NotchAgent/Core/Models/Usage.swift")
        let gaugeBody = source.components(
            separatedBy: "public static func from(_ snapshot: UsageSnapshot?) -> GaugeMetric?"
        ).last ?? ""

        let blockedIndex = gaugeBody.range(of: "quotaStatus == .blocked")?.lowerBound
        let weeklyIndex = gaugeBody.range(of: "let weeklyExhausted")?.lowerBound
        let sessionIndex = gaugeBody.range(of: "if let percent = snapshot?.session?.usedPercent")?.lowerBound
        let weeklyFallbackIndex = gaugeBody.range(of: "if let percent = snapshot?.weekly?.usedPercent")?.lowerBound

        XCTAssertNotNil(blockedIndex, "o gauge deve checar blocked primeiro")
        XCTAssertNotNil(weeklyIndex, "o gauge deve checar weeklyExhausted")
        XCTAssertNotNil(sessionIndex, "o gauge deve ter o ramo da sessão")
        XCTAssertNotNil(weeklyFallbackIndex, "o gauge deve ter o fallback semanal")
        XCTAssertLessThan(blockedIndex!, weeklyIndex!, "blocked deve vir antes de weeklyExhausted")
        XCTAssertLessThan(weeklyIndex!, sessionIndex!, "weeklyExhausted deve vencer a sessão")
        XCTAssertLessThan(sessionIndex!, weeklyFallbackIndex!, "sessão deve vir antes do fallback semanal")
    }

    /// 2. Nenhuma view deriva número/veredito fora do gauge: o burnPanel
    /// DEVE consumir `GaugeMetric.from` + `gaugeExhausted`, nunca o
    /// percentual cru da sessão como headline (regressão de 20/08).
    func testBurnPanelDerivesHeadlineFromGaugeNotRawSession() {
        let source = source("Sources/NotchAgent/Features/NotchOverlay/Views/NotchExpandedView.swift")
        let panel = source.components(separatedBy: "private func burnPanel").last ?? ""

        XCTAssertTrue(panel.contains("let metric = GaugeMetric.from(snapshot)"), "burnPanel deve usar o gauge")
        XCTAssertTrue(panel.contains("let gaugeExhausted"), "burnPanel deve derivar o esgotamento do gauge")
        XCTAssertTrue(
            panel.contains("let used = gaugeExhausted ? metric?.used : session?.usedPercent"),
            "o número grande vem do gauge quando esgotado — nunca do percentual cru da sessão"
        )
        XCTAssertTrue(
            panel.contains("gaugeExhausted: gaugeExhausted"),
            "o veredito deve receber o esgotamento do gauge"
        )
    }

    /// 3. O runner segue o MESMO gauge das wings — o jogo nunca pode
    /// parecer relaxado enquanto o medidor visível está vermelho.
    func testRunnerGameUsesTheSharedGauge() {
        let source = source("Sources/NotchAgent/Features/NotchOverlay/Components/NotchRunnerView.swift")
        let game = source.components(separatedBy: "var runnerGame").last ?? ""
        XCTAssertTrue(game.contains("GaugeMetric.from(snapshot)"), "o runner deve derivar do gauge compartilhado")
    }
}
