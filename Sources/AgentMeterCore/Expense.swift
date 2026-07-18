import Foundation

public enum SpendDisplayCurrency: String, CaseIterable, Codable, Sendable {
    case brl
    case usd

    public var code: String { rawValue.uppercased() }
}

/// A one-off amount paid beyond a recurring plan. It is deliberately local and
/// user-entered: no credentials, billing pages, or provider APIs are required.
public struct AIExpense: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case apiUsage
        case usageCredits
        case tokenPurchase
        case other
    }

    public enum Source: String, CaseIterable, Codable, Sendable {
        case manual
        case officialInvoice
        case localEstimate
    }

    public var id: UUID
    public var provider: AgentMeterProvider
    public var title: String
    public var amountBRL: Decimal
    public var kind: Kind
    public var source: Source
    public var incurredAt: Date

    public init(
        id: UUID = UUID(),
        provider: AgentMeterProvider,
        title: String,
        amountBRL: Decimal,
        kind: Kind,
        source: Source = .manual,
        incurredAt: Date = .now
    ) {
        self.id = id
        self.provider = provider
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.amountBRL = max(amountBRL, 0)
        self.kind = kind
        self.source = source
        self.incurredAt = incurredAt
    }
}

public struct MonthlySpendSummary: Equatable, Sendable {
    public var planChargesBRL: Decimal
    public var extraChargesBRL: Decimal
    public var forecastPlanBRL: Decimal

    public init(
        history: [SubscriptionHistoryEvent],
        expenses: [AIExpense],
        subscriptions: [AISubscription] = [],
        month: Date = .now,
        calendar: Calendar = .current
    ) {
        planChargesBRL = history.totalRenewed(in: month, calendar: calendar)
        extraChargesBRL = expenses
            .filter {
                $0.source != .localEstimate
                    && calendar.isDate($0.incurredAt, equalTo: month, toGranularity: .month)
            }
            .reduce(0) { $0 + $1.amountBRL }
        forecastPlanBRL = subscriptions
            .filter { $0.isActive && calendar.isDate($0.nextRenewalDate, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.cycleTotalBRL }
    }

    /// Confirmed payments in the calendar month. Never includes token math.
    public var paidBRL: Decimal { planChargesBRL + extraChargesBRL }
    public var totalBRL: Decimal { planChargesBRL + extraChargesBRL }
}

public enum MonthlyBudgetLevel: Int, Codable, Sendable, Equatable {
    case normal = 0
    case warning = 70
    case critical = 90
    case exceeded = 100
}

public struct MonthlyBudgetStatus: Equatable, Sendable {
    public var budgetBRL: Decimal
    public var paidBRL: Decimal
    public var projectedBRL: Decimal

    public init(summary: MonthlySpendSummary, budgetBRL: Decimal) {
        self.budgetBRL = max(budgetBRL, 0)
        paidBRL = summary.paidBRL
        projectedBRL = summary.paidBRL + summary.forecastPlanBRL
    }

    public var projectedPercent: Double {
        guard budgetBRL > 0 else { return 0 }
        return Double(truncating: (projectedBRL / budgetBRL) as NSDecimalNumber) * 100
    }

    public var level: MonthlyBudgetLevel {
        switch projectedPercent {
        case 100...: .exceeded
        case 90...: .critical
        case 70...: .warning
        default: .normal
        }
    }
}

public struct MonthlyBudgetAlert: Equatable, Sendable {
    public var level: MonthlyBudgetLevel
    public var percent: Double

    public init(level: MonthlyBudgetLevel, percent: Double) {
        self.level = level
        self.percent = percent
    }
}
