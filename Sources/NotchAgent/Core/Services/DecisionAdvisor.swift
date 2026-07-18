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
}
