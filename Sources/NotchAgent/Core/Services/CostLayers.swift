import Foundation
import AgentMeterCore

/// Keeps billing truth separate from transcript-derived token pricing.
struct EstimatedCostLayers: Equatable {
    var totalUSD: Double
    var byProvider: [ProviderID: Double]

    static func fromSnapshots(_ snapshots: [ProviderID: UsageSnapshot]) -> EstimatedCostLayers {
        var byProvider: [ProviderID: Double] = [:]
        for (provider, snapshot) in snapshots {
            guard let cost = snapshot.weekly?.cost?.amountUSD, cost > 0 else { continue }
            byProvider[provider] = cost
        }
        return EstimatedCostLayers(totalUSD: byProvider.values.reduce(0, +), byProvider: byProvider)
    }
}

struct ProviderReconciliation: Identifiable {
    var provider: AgentMeterProvider
    var officialBRL: Decimal
    var estimatedUSD: Double
    var id: AgentMeterProvider { provider }
}

enum CostReconciliation {
    static func currentMonth(expenses: [AIExpense], estimates: EstimatedCostLayers, calendar: Calendar = .current) -> [ProviderReconciliation] {
        let official = expenses
            .filter { $0.source == .officialInvoice && calendar.isDate($0.incurredAt, equalTo: .now, toGranularity: .month) }
            .reduce(into: [AgentMeterProvider: Decimal]()) { $0[$1.provider, default: 0] += $1.amountBRL }
        let mapped: [AgentMeterProvider: Double] = [.claude: estimates.byProvider[.claudeCode] ?? 0, .chatGPT: estimates.byProvider[.codex] ?? 0, .gemini: estimates.byProvider[.geminiCLI] ?? 0]
        return AgentMeterProvider.allCases.compactMap { provider in
            let paid = official[provider] ?? 0
            let estimated = mapped[provider] ?? 0
            return paid > 0 || estimated > 0 ? ProviderReconciliation(provider: provider, officialBRL: paid, estimatedUSD: estimated) : nil
        }
    }
}
