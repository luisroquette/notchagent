import Combine
import Foundation

/// UI-facing façade. Domain rules, financial calculations, and persistence live
/// in SubscriptionLedger, SpendingEngine, and SubscriptionRepository.
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
        SubscriptionSummary(subscriptions: ledger.subscriptions)
    }

    public var monthlySpend: MonthlySpendSummary {
        SpendingEngine.summary(for: ledger)
    }

    public var monthlyBudgetStatus: MonthlyBudgetStatus? {
        SpendingEngine.budgetStatus(for: ledger, monthlyBudgetBRL: monthlyBudgetBRL)
    }

    public var onMonthlyBudgetAlert: ((MonthlyBudgetAlert) -> Void)?

    private var ledger: SubscriptionLedger
    private let repository: any SubscriptionRepositoryProtocol

    public convenience init(
        defaults: UserDefaults = .standard,
        storageKey: String = "agentmeter.subscriptions.v1"
    ) {
        self.init(repository: SubscriptionRepository(defaults: defaults, storageKey: storageKey))
    }

    public init(repository: any SubscriptionRepositoryProtocol) {
        self.repository = repository
        let ledger = repository.loadLedger()
        let preferences = repository.loadPreferences()
        self.ledger = ledger
        subscriptions = ledger.subscriptions
        history = ledger.history
        expenses = ledger.expenses
        displayCurrency = preferences.displayCurrency
        brlPerUSD = preferences.brlPerUSD
        monthlyBudgetBRL = preferences.monthlyBudgetBRL
        isCloudSyncEnabled = preferences.isCloudSyncEnabled
        cloudSyncState = repository.cloudSyncState

        repository.onCloudSyncStateChange = { [weak self] state in
            self?.cloudSyncState = state
        }
        repository.onSynchronized = { [weak self] snapshot in
            self?.applySynchronizedSnapshot(snapshot)
        }
    }

    public func add(_ subscription: AISubscription) {
        ledger.add(subscription)
        commit()
    }

    /// Imports only subscriptions that do not already exist locally. Callers
    /// present the parser preview first, then use this method after confirmation.
    @discardableResult
    public func importSubscriptions(_ candidates: [AISubscription]) -> Int {
        let accepted = ledger.importSubscriptions(candidates)
        guard accepted > 0 else { return 0 }
        commit()
        return accepted
    }

    public func update(_ subscription: AISubscription) {
        guard ledger.update(subscription) else { return }
        commit()
    }

    public func remove(id: AISubscription.ID) {
        guard ledger.remove(id: id) else { return }
        commit()
    }

    public func addExpense(_ expense: AIExpense) {
        ledger.addExpense(expense)
        commit(syncToCloud: false)
    }

    public func addExpenses(_ newExpenses: [AIExpense]) {
        guard !newExpenses.isEmpty else { return }
        ledger.addExpenses(newExpenses)
        commit(syncToCloud: false)
    }

    public func removeExpense(id: AIExpense.ID) {
        guard ledger.removeExpense(id: id) else { return }
        commit(syncToCloud: false)
    }

    public func setDisplayCurrency(_ currency: SpendDisplayCurrency) {
        displayCurrency = currency
        repository.saveDisplayCurrency(currency)
    }

    public func setBRLPerUSD(_ rate: Decimal?) {
        brlPerUSD = rate.flatMap { $0 > 0 ? $0 : nil }
        repository.saveBRLPerUSD(brlPerUSD)
    }

    public func setMonthlyBudgetBRL(_ amount: Decimal?) {
        monthlyBudgetBRL = amount.flatMap { $0 > 0 ? $0 : nil }
        repository.saveMonthlyBudgetBRL(monthlyBudgetBRL)
        evaluateBudget()
    }

    public func format(_ amountBRL: Decimal, compact: Bool = false) -> String {
        SpendingEngine.format(
            amountBRL,
            currency: displayCurrency,
            brlPerUSD: brlPerUSD,
            compact: compact
        )
    }

    public func formatEstimatedUSD(_ amountUSD: Double, compact: Bool = false) -> String {
        SpendingEngine.formatEstimatedUSD(
            amountUSD,
            currency: displayCurrency,
            brlPerUSD: brlPerUSD,
            compact: compact
        )
    }

    /// Confirms a charge and advances the subscription to its next billing cycle.
    @discardableResult
    public func confirmRenewal(id: AISubscription.ID, on date: Date = .now) -> AISubscription? {
        guard let renewed = ledger.confirmRenewal(id: id, on: date) else { return nil }
        commit()
        return renewed
    }

    public func setCloudSyncEnabled(_ enabled: Bool) async {
        isCloudSyncEnabled = enabled
        repository.setCloudSyncEnabled(enabled)
        guard enabled else { return }
        await repository.syncNow(ledger.syncSnapshot)
    }

    public func syncIfEnabled() async {
        guard isCloudSyncEnabled else { return }
        await repository.syncNow(ledger.syncSnapshot)
    }

    public func syncNow() async {
        guard isCloudSyncEnabled else { return }
        await repository.syncNow(ledger.syncSnapshot)
    }

    private func commit(syncToCloud: Bool = true) {
        publishLedger()
        repository.save(ledger)
        if syncToCloud {
            repository.queueCloudSync(ledger.syncSnapshot)
        }
        evaluateBudget()
    }

    private func publishLedger() {
        subscriptions = ledger.subscriptions
        history = ledger.history
        expenses = ledger.expenses
    }

    private func applySynchronizedSnapshot(_ snapshot: SubscriptionSyncSnapshot) {
        ledger.apply(snapshot)
        publishLedger()
        repository.save(ledger)
        evaluateBudget()
    }

    private func evaluateBudget() {
        guard let alert = SpendingEngine.budgetAlert(for: monthlyBudgetStatus) else { return }
        guard repository.claimBudgetAlert(level: alert.level, on: .now) else { return }
        onMonthlyBudgetAlert?(alert)
    }
}
