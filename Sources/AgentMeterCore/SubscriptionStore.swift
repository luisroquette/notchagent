import Combine
import Foundation

@MainActor
public final class SubscriptionStore: ObservableObject {
    @Published public private(set) var subscriptions: [AISubscription]
    @Published public private(set) var history: [SubscriptionHistoryEvent]
    @Published public private(set) var expenses: [AIExpense]
    @Published public private(set) var displayCurrency: SpendDisplayCurrency
    @Published public private(set) var brlPerUSD: Decimal?
    @Published public private(set) var monthlyBudgetBRL: Decimal?
    @Published public private(set) var isCloudSyncEnabled: Bool
    @Published public private(set) var cloudSyncState: CloudSyncState

    public var summary: SubscriptionSummary {
        SubscriptionSummary(subscriptions: subscriptions)
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private var tombstones: [UUID: Date]
    private var cloudSync: CloudSubscriptionSync?
    private var isSyncing = false
    private var hasQueuedSync = false
    private var retryAttempt = 0
    private var retryTask: Task<Void, Never>?
    public var onMonthlyBudgetAlert: ((MonthlyBudgetAlert) -> Void)?

    public init(defaults: UserDefaults = .standard, storageKey: String = "agentmeter.subscriptions.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        subscriptions = Self.load(defaults: defaults, key: storageKey)
        history = Self.loadHistory(defaults: defaults, key: "\(storageKey).history")
        expenses = Self.loadExpenses(defaults: defaults, key: "\(storageKey).expenses")
        displayCurrency = SpendDisplayCurrency(rawValue: defaults.string(forKey: "\(storageKey).display-currency") ?? "brl") ?? .brl
        brlPerUSD = Self.loadDecimal(defaults: defaults, key: "\(storageKey).brl-per-usd")
        monthlyBudgetBRL = Self.loadDecimal(defaults: defaults, key: "\(storageKey).monthly-budget")
        tombstones = Self.loadTombstones(defaults: defaults, key: "\(storageKey).tombstones")
        let cloudEnabled = defaults.bool(forKey: "\(storageKey).icloud-enabled")
        isCloudSyncEnabled = cloudEnabled
        cloudSyncState = cloudEnabled ? .syncing : .localOnly
    }

    public func add(_ subscription: AISubscription) {
        subscriptions.append(subscription)
        tombstones.removeValue(forKey: subscription.id)
        subscriptions.sort { $0.nextRenewalDate < $1.nextRenewalDate }
        save()
        queueCloudSync()
        evaluateBudget()
    }

    /// Imports only subscriptions that do not already exist locally. Callers
    /// present the parser preview first, then use this method after confirmation.
    @discardableResult
    public func importSubscriptions(_ candidates: [AISubscription]) -> Int {
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
        subscriptions.sort { $0.nextRenewalDate < $1.nextRenewalDate }
        save()
        queueCloudSync()
        evaluateBudget()
        return accepted.count
    }

    public func update(_ subscription: AISubscription) {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
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
        subscriptions.sort { $0.nextRenewalDate < $1.nextRenewalDate }
        save()
        queueCloudSync()
        evaluateBudget()
    }

    public func remove(id: AISubscription.ID) {
        guard let subscription = subscriptions.first(where: { $0.id == id }) else { return }
        subscriptions.removeAll { $0.id == id }
        record(.init(
            subscriptionID: subscription.id,
            provider: subscription.provider,
            planName: subscription.planName,
            kind: .cancelled,
            amountBRL: subscription.cycleTotalBRL
        ))
        tombstones[id] = .now
        save()
        queueCloudSync()
        evaluateBudget()
    }

    public var monthlySpend: MonthlySpendSummary {
        MonthlySpendSummary(history: history, expenses: expenses, subscriptions: subscriptions)
    }

    public func addExpense(_ expense: AIExpense) {
        expenses.append(expense)
        expenses.sort { $0.incurredAt > $1.incurredAt }
        save()
        evaluateBudget()
    }

    public func addExpenses(_ newExpenses: [AIExpense]) {
        guard !newExpenses.isEmpty else { return }
        expenses.append(contentsOf: newExpenses)
        expenses.sort { $0.incurredAt > $1.incurredAt }
        save()
        evaluateBudget()
    }

    public func removeExpense(id: AIExpense.ID) {
        expenses.removeAll { $0.id == id }
        save()
        evaluateBudget()
    }

    public func setDisplayCurrency(_ currency: SpendDisplayCurrency) {
        displayCurrency = currency
        defaults.set(currency.rawValue, forKey: "\(storageKey).display-currency")
    }

    public func setBRLPerUSD(_ rate: Decimal?) {
        brlPerUSD = rate.flatMap { $0 > 0 ? $0 : nil }
        if let brlPerUSD {
            defaults.set(NSDecimalNumber(decimal: brlPerUSD).stringValue, forKey: "\(storageKey).brl-per-usd")
        } else {
            defaults.removeObject(forKey: "\(storageKey).brl-per-usd")
        }
    }

    public var monthlyBudgetStatus: MonthlyBudgetStatus? {
        monthlyBudgetBRL.map { MonthlyBudgetStatus(summary: monthlySpend, budgetBRL: $0) }
    }

    public func setMonthlyBudgetBRL(_ amount: Decimal?) {
        monthlyBudgetBRL = amount.flatMap { $0 > 0 ? $0 : nil }
        if let monthlyBudgetBRL {
            defaults.set(NSDecimalNumber(decimal: monthlyBudgetBRL).stringValue, forKey: "\(storageKey).monthly-budget")
        } else {
            defaults.removeObject(forKey: "\(storageKey).monthly-budget")
        }
        evaluateBudget()
    }

    public func format(_ amountBRL: Decimal, compact: Bool = false) -> String {
        let value: Decimal
        let currencyCode: String
        switch displayCurrency {
        case .brl:
            value = amountBRL
            currencyCode = "BRL"
        case .usd:
            guard let brlPerUSD else { return "USD —" }
            value = amountBRL / brlPerUSD
            currencyCode = "USD"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: displayCurrency == .brl ? "pt_BR" : "en_US")
        if compact {
            formatter.maximumFractionDigits = value >= 100 ? 0 : 2
            formatter.minimumFractionDigits = 0
        }
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    /// Token-based costs originate in USD public price tables. They remain
    /// visibly estimated and are only converted when the user supplied a rate.
    public func formatEstimatedUSD(_ amountUSD: Double, compact: Bool = false) -> String {
        guard amountUSD > 0 else { return "—" }
        if displayCurrency == .brl, let brlPerUSD {
            return "~" + format(Decimal(amountUSD) * brlPerUSD, compact: compact)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        if compact {
            formatter.maximumFractionDigits = amountUSD >= 100 ? 0 : 2
            formatter.minimumFractionDigits = 0
        }
        return "~" + (formatter.string(from: amountUSD as NSNumber) ?? "$—")
    }

    /// Confirms a charge and advances the subscription to its next billing cycle.
    @discardableResult
    public func confirmRenewal(id: AISubscription.ID, on date: Date = .now) -> AISubscription? {
        guard let index = subscriptions.firstIndex(where: { $0.id == id && $0.isActive }) else { return nil }
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
        subscriptions.sort { $0.nextRenewalDate < $1.nextRenewalDate }
        save()
        queueCloudSync()
        evaluateBudget()
        return renewed
    }

    public func setCloudSyncEnabled(_ enabled: Bool) async {
        isCloudSyncEnabled = enabled
        defaults.set(enabled, forKey: "\(storageKey).icloud-enabled")
        guard enabled else {
            retryTask?.cancel()
            retryTask = nil
            retryAttempt = 0
            cloudSyncState = .localOnly
            return
        }
        await syncNow()
    }

    public func syncIfEnabled() async {
        guard isCloudSyncEnabled else { return }
        await syncNow()
    }

    public func syncNow() async {
        guard isCloudSyncEnabled else { return }
        guard !isSyncing else {
            hasQueuedSync = true
            return
        }
        retryTask?.cancel()
        retryTask = nil
        isSyncing = true
        defer {
            isSyncing = false
            if hasQueuedSync {
                hasQueuedSync = false
                Task { await syncNow() }
            }
        }
        cloudSyncState = .syncing
        let service = cloudSync ?? CloudSubscriptionSync()
        cloudSync = service
        do {
            let merged = try await service.synchronize(
                SubscriptionSyncSnapshot(subscriptions: subscriptions, tombstones: tombstones, history: history)
            )
            subscriptions = merged.subscriptions
            tombstones = merged.tombstones
            history = merged.history
            save()
            cloudSyncState = .synced(.now)
            retryAttempt = 0
        } catch CloudSyncFailure.accountUnavailable {
            cloudSyncState = .unavailable
        } catch {
            scheduleRetry()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        defaults.set(data, forKey: storageKey)
        if let tombstoneData = try? JSONEncoder().encode(tombstones) {
            defaults.set(tombstoneData, forKey: "\(storageKey).tombstones")
        }
        if let historyData = try? JSONEncoder().encode(history) {
            defaults.set(historyData, forKey: "\(storageKey).history")
        }
        if let expenseData = try? JSONEncoder().encode(expenses) {
            defaults.set(expenseData, forKey: "\(storageKey).expenses")
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> [AISubscription] {
        guard let data = defaults.data(forKey: key),
              let subscriptions = try? JSONDecoder().decode([AISubscription].self, from: data) else {
            return []
        }
        return subscriptions.sorted { $0.nextRenewalDate < $1.nextRenewalDate }
    }

    private static func loadTombstones(defaults: UserDefaults, key: String) -> [UUID: Date] {
        guard let data = defaults.data(forKey: key),
              let tombstones = try? JSONDecoder().decode([UUID: Date].self, from: data) else {
            return [:]
        }
        return tombstones
    }

    private static func loadExpenses(defaults: UserDefaults, key: String) -> [AIExpense] {
        guard let data = defaults.data(forKey: key),
              let expenses = try? JSONDecoder().decode([AIExpense].self, from: data) else {
            return []
        }
        return expenses.sorted { $0.incurredAt > $1.incurredAt }
    }

    private static func loadDecimal(defaults: UserDefaults, key: String) -> Decimal? {
        defaults.string(forKey: key).flatMap { Decimal(string: $0) }
    }

    private static func loadHistory(defaults: UserDefaults, key: String) -> [SubscriptionHistoryEvent] {
        guard let data = defaults.data(forKey: key),
              let events = try? JSONDecoder().decode([SubscriptionHistoryEvent].self, from: data) else {
            return []
        }
        return events.sorted { $0.occurredAt > $1.occurredAt }
    }

    private func record(_ event: SubscriptionHistoryEvent) {
        history.append(event)
        let cutoff = Calendar.current.date(byAdding: .month, value: -24, to: .now) ?? .distantPast
        history.removeAll { $0.occurredAt < cutoff }
        history.sort { $0.occurredAt > $1.occurredAt }
    }

    private func evaluateBudget() {
        guard let status = monthlyBudgetStatus, status.level != .normal else { return }
        let key = "\(storageKey).budget-alerts.\(Self.monthKey(Date()))"
        var fired = Set(defaults.stringArray(forKey: key) ?? [])
        let level = String(status.level.rawValue)
        guard fired.insert(level).inserted else { return }
        defaults.set(Array(fired), forKey: key)
        onMonthlyBudgetAlert?(MonthlyBudgetAlert(level: status.level, percent: status.projectedPercent))
    }

    private static func monthKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    private func queueCloudSync() {
        guard isCloudSyncEnabled else { return }
        Task { await syncNow() }
    }

    private func scheduleRetry() {
        guard retryAttempt < 3 else {
            cloudSyncState = .failed
            return
        }
        retryAttempt += 1
        let delay = min(pow(2, Double(retryAttempt)) * 5, 60)
        let retryDate = Date().addingTimeInterval(delay)
        cloudSyncState = .waitingToRetry(retryDate)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }
}
