import Foundation

/// Pure domain state for subscriptions, expenses, renewal history, and cloud tombstones.
/// It deliberately has no persistence, CloudKit, formatting, or UI responsibilities.
public struct SubscriptionLedger: Equatable, Sendable {
    public private(set) var subscriptions: [AISubscription]
    public private(set) var history: [SubscriptionHistoryEvent]
    public private(set) var expenses: [AIExpense]
    public private(set) var tombstones: [UUID: Date]

    public init(
        subscriptions: [AISubscription] = [],
        history: [SubscriptionHistoryEvent] = [],
        expenses: [AIExpense] = [],
        tombstones: [UUID: Date] = [:]
    ) {
        self.subscriptions = subscriptions.sorted { $0.nextRenewalDate < $1.nextRenewalDate }
        self.history = history.sorted { $0.occurredAt > $1.occurredAt }
        self.expenses = expenses.sorted { $0.incurredAt > $1.incurredAt }
        self.tombstones = tombstones
    }

    public var syncSnapshot: SubscriptionSyncSnapshot {
        SubscriptionSyncSnapshot(
            subscriptions: subscriptions,
            tombstones: tombstones,
            history: history
        )
    }

    public mutating func apply(_ snapshot: SubscriptionSyncSnapshot) {
        subscriptions = snapshot.subscriptions.sorted { $0.nextRenewalDate < $1.nextRenewalDate }
        history = snapshot.history.sorted { $0.occurredAt > $1.occurredAt }
        tombstones = snapshot.tombstones
    }

    public mutating func add(_ subscription: AISubscription) {
        subscriptions.append(subscription)
        tombstones.removeValue(forKey: subscription.id)
        sortSubscriptions()
    }

    @discardableResult
    public mutating func importSubscriptions(_ candidates: [AISubscription]) -> Int {
        var keys = Set(subscriptions.filter(\.isActive).map(SubscriptionImportParser.duplicateKey))
        let accepted = candidates.filter { keys.insert(SubscriptionImportParser.duplicateKey($0)).inserted }
        guard !accepted.isEmpty else { return 0 }

        subscriptions.append(contentsOf: accepted)
        for subscription in accepted {
            record(.init(
                subscriptionID: subscription.id,
                provider: subscription.provider,
                planName: subscription.planName,
                kind: .imported,
                amountBRL: subscription.cycleTotalBRL
            ))
        }
        sortSubscriptions()
        return accepted.count
    }

    @discardableResult
    public mutating func update(_ subscription: AISubscription) -> Bool {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else {
            return false
        }
        let current = subscriptions[index]
        var updated = subscription
        updated.updatedAt = .now
        subscriptions[index] = updated
        if current.cycleTotalBRL != updated.cycleTotalBRL || current.billingCycle != updated.billingCycle {
            record(.init(
                subscriptionID: updated.id,
                provider: updated.provider,
                planName: updated.planName,
                kind: .priceChanged,
                amountBRL: updated.cycleTotalBRL
            ))
        }
        tombstones.removeValue(forKey: updated.id)
        sortSubscriptions()
        return true
    }

    @discardableResult
    public mutating func remove(id: AISubscription.ID) -> Bool {
        guard let subscription = subscriptions.first(where: { $0.id == id }) else {
            return false
        }
        subscriptions.removeAll { $0.id == id }
        record(.init(
            subscriptionID: subscription.id,
            provider: subscription.provider,
            planName: subscription.planName,
            kind: .cancelled,
            amountBRL: subscription.cycleTotalBRL
        ))
        tombstones[id] = .now
        return true
    }

    public mutating func addExpense(_ expense: AIExpense) {
        expenses.append(expense)
        sortExpenses()
    }

    public mutating func addExpenses(_ newExpenses: [AIExpense]) {
        expenses.append(contentsOf: newExpenses)
        sortExpenses()
    }

    @discardableResult
    public mutating func removeExpense(id: AIExpense.ID) -> Bool {
        let previousCount = expenses.count
        expenses.removeAll { $0.id == id }
        return expenses.count != previousCount
    }

    @discardableResult
    public mutating func confirmRenewal(
        id: AISubscription.ID,
        on date: Date = .now
    ) -> AISubscription? {
        guard let index = subscriptions.firstIndex(where: { $0.id == id && $0.isActive }) else {
            return nil
        }
        var renewed = subscriptions[index]
        renewed.nextRenewalDate = renewed.nextRenewal(after: date)
        renewed.updatedAt = .now
        subscriptions[index] = renewed
        record(.init(
            subscriptionID: renewed.id,
            provider: renewed.provider,
            planName: renewed.planName,
            kind: .renewalConfirmed,
            amountBRL: renewed.cycleTotalBRL,
            occurredAt: date
        ))
        sortSubscriptions()
        return renewed
    }

    private mutating func record(_ event: SubscriptionHistoryEvent) {
        history.append(event)
        let cutoff = Calendar.current.date(byAdding: .month, value: -24, to: .now) ?? .distantPast
        history.removeAll { $0.occurredAt < cutoff }
        history.sort { $0.occurredAt > $1.occurredAt }
    }

    private mutating func sortSubscriptions() {
        subscriptions.sort { $0.nextRenewalDate < $1.nextRenewalDate }
    }

    private mutating func sortExpenses() {
        expenses.sort { $0.incurredAt > $1.incurredAt }
    }
}
