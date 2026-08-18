import AgentMeterCore
import Foundation

struct DecisionAdvice: Identifiable, Equatable {
    enum Severity: Int { case normal, warning, critical }
    var id: String { title }
    var title: String
    var detail: String
    var severity: Severity
}

enum DecisionAdvisor {
    static let cacheShareMin = 0.25
    static let minTokensForAdvice = 50_000

    static func advise(snapshots: [ProviderID: UsageSnapshot], budget: MonthlyBudgetStatus?) -> [DecisionAdvice] {
        var advice: [DecisionAdvice] = []
        if let budget {
            switch budget.level {
            case .exceeded:
                advice.append(.init(title: "Evite gasto adicional", detail: "A previsão já excede o orçamento mensal.", severity: .critical))
            case .critical:
                advice.append(.init(title: "Reduza modelos caros", detail: "A previsão atingiu \(Int(budget.projectedPercent.rounded()))% do orçamento.", severity: .critical))
            case .warning:
                advice.append(.init(title: "Use modelos caros com critério", detail: "A previsão atingiu \(Int(budget.projectedPercent.rounded()))% do orçamento.", severity: .warning))
            case .normal: break
            }
        }
        for provider in ProviderID.allCases {
            if let coldCache = coldCacheAdvice(snapshots[provider]) { advice.append(coldCache) }
            guard let gauge = GaugeMetric.from(snapshots[provider]), gauge.remaining <= 20 else { continue }
            advice.append(.init(title: "Poupe \(provider.shortName)", detail: "Restam \(Int(gauge.remaining.rounded()))% da quota atual.", severity: .warning))
        }
        let estimates = EstimatedCostLayers.fromSnapshots(snapshots)
        if let driver = estimates.byProvider.max(by: { $0.value < $1.value }), driver.value > 0 {
            advice.append(.init(title: "Maior custo local: \(driver.key.shortName)", detail: "~$\(String(format: "%.2f", driver.value)) nos últimos 7 dias; é estimativa de tokens.", severity: .normal))
        }
        if advice.isEmpty {
            advice.append(.init(title: "Pode continuar", detail: "Sem pressão de orçamento ou quota detectada agora.", severity: .normal))
        }
        return Array(advice.prefix(3))
    }

    /// Sessão com pouco cache lido (releitura de contexto cara). Só dispara
    /// acima do piso de tokens — sessão minúscula não merece conselho.
    private static func coldCacheAdvice(_ snapshot: UsageSnapshot?) -> DecisionAdvice? {
        guard let session = snapshot?.session,
              session.tokens.total >= minTokensForAdvice else { return nil }
        let share = Double(session.tokens.cacheRead) / Double(max(session.tokens.total, 1))
        guard share < cacheShareMin else { return nil }
        let pct = Int((share * 100).rounded())
        return DecisionAdvice(
            title: "Sessão fria de cache",
            detail: "Apenas \(pct)% dos tokens desta sessão são leitura de cache; manter a sessão ativa reutiliza contexto (cache expira em 1h).",
            severity: .warning
        )
    }
}
