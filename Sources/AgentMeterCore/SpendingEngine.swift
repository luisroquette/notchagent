import Foundation

/// Pure financial projections and display conversion for subscription data.
public enum SpendingEngine {
    public static func summary(for ledger: SubscriptionLedger) -> MonthlySpendSummary {
        MonthlySpendSummary(
            history: ledger.history,
            expenses: ledger.expenses,
            subscriptions: ledger.subscriptions
        )
    }

    public static func budgetStatus(
        for ledger: SubscriptionLedger,
        monthlyBudgetBRL: Decimal?
    ) -> MonthlyBudgetStatus? {
        monthlyBudgetBRL.map {
            MonthlyBudgetStatus(summary: summary(for: ledger), budgetBRL: $0)
        }
    }

    public static func budgetAlert(for status: MonthlyBudgetStatus?) -> MonthlyBudgetAlert? {
        guard let status, status.level != .normal else { return nil }
        return MonthlyBudgetAlert(level: status.level, percent: status.projectedPercent)
    }

    public static func format(
        _ amountBRL: Decimal,
        currency: SpendDisplayCurrency,
        brlPerUSD: Decimal?,
        compact: Bool = false
    ) -> String {
        let value: Decimal
        let currencyCode: String
        switch currency {
        case .brl:
            value = amountBRL
            currencyCode = "BRL"
        case .usd:
            guard let brlPerUSD else { return "USD —" }
            value = amountBRL / brlPerUSD
            currencyCode = "USD"
        }
        return formatted(value, currencyCode: currencyCode, compact: compact)
    }

    /// Token-based costs remain visibly estimated and are converted only with a known rate.
    public static func formatEstimatedUSD(
        _ amountUSD: Double,
        currency: SpendDisplayCurrency,
        brlPerUSD: Decimal?,
        compact: Bool = false
    ) -> String {
        guard amountUSD > 0 else { return "—" }
        if currency == .brl, let brlPerUSD {
            return "~" + format(
                Decimal(amountUSD) * brlPerUSD,
                currency: .brl,
                brlPerUSD: brlPerUSD,
                compact: compact
            )
        }
        return "~" + formatted(
            Decimal(amountUSD),
            currencyCode: "USD",
            compact: compact
        )
    }

    private static func formatted(
        _ value: Decimal,
        currencyCode: String,
        compact: Bool
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: currencyCode == "BRL" ? "pt_BR" : "en_US")
        if compact {
            formatter.maximumFractionDigits = value >= 100 ? 0 : 2
            formatter.minimumFractionDigits = 0
        }
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }
}
