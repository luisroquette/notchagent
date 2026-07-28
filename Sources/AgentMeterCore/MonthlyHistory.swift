import Foundation

public struct MonthlyProviderSpend: Identifiable, Equatable, Sendable {
    public var month: Date
    public var provider: AgentMeterProvider
    public var amountBRL: Decimal
    public var id: String { "\(month.timeIntervalSince1970)-\(provider.rawValue)" }
}

public enum FinancialHistory {
    public static func monthlyPayments(
        history: [SubscriptionHistoryEvent], expenses: [AIExpense], months: Int = 6, now: Date = .now, calendar: Calendar = .current
    ) -> [MonthlyProviderSpend] {
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let cutoff = calendar.date(byAdding: .month, value: -(max(1, months) - 1), to: current) ?? current
        var totals: [String: MonthlyProviderSpend] = [:]
        func add(_ date: Date, _ provider: AgentMeterProvider, _ amount: Decimal) {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            guard month >= cutoff else { return }
            let key = "\(month.timeIntervalSince1970)-\(provider.rawValue)"
            var item = totals[key] ?? .init(month: month, provider: provider, amountBRL: 0)
            item.amountBRL += amount
            totals[key] = item
        }
        for event in history where event.kind == .renewalConfirmed { add(event.occurredAt, event.provider, event.amountBRL) }
        for expense in expenses where expense.source != .localEstimate { add(expense.incurredAt, expense.provider, expense.amountBRL) }
        return totals.values.sorted { $0.month > $1.month || ($0.month == $1.month && $0.provider.rawValue < $1.provider.rawValue) }
    }

    public static func csv(_ rows: [MonthlyProviderSpend]) -> String {
        "month,provider,paid_brl\n" + rows.map { row in
            let month = row.month.formatted(.iso8601.year().month())
            return "\(month),\(row.provider.rawValue),\(NSDecimalNumber(decimal: row.amountBRL).stringValue)"
        }.joined(separator: "\n") + "\n"
    }
}
