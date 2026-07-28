import Foundation

public struct SubscriptionStorePreferences: Equatable, Sendable {
    public var displayCurrency: SpendDisplayCurrency
    public var brlPerUSD: Decimal?
    public var monthlyBudgetBRL: Decimal?
    public var isCloudSyncEnabled: Bool

    public init(
        displayCurrency: SpendDisplayCurrency = .brl,
        brlPerUSD: Decimal? = nil,
        monthlyBudgetBRL: Decimal? = nil,
        isCloudSyncEnabled: Bool = false
    ) {
        self.displayCurrency = displayCurrency
        self.brlPerUSD = brlPerUSD
        self.monthlyBudgetBRL = monthlyBudgetBRL
        self.isCloudSyncEnabled = isCloudSyncEnabled
    }
}

@MainActor
public protocol SubscriptionRepositoryProtocol: AnyObject {
    var isCloudSyncEnabled: Bool { get }
    var cloudSyncState: CloudSyncState { get }
    var onCloudSyncStateChange: (@MainActor (CloudSyncState) -> Void)? { get set }
    var onSynchronized: (@MainActor (SubscriptionSyncSnapshot) -> Void)? { get set }

    func loadLedger() -> SubscriptionLedger
    func loadPreferences() -> SubscriptionStorePreferences
    func save(_ ledger: SubscriptionLedger)
    func saveDisplayCurrency(_ currency: SpendDisplayCurrency)
    func saveBRLPerUSD(_ rate: Decimal?)
    func saveMonthlyBudgetBRL(_ amount: Decimal?)
    func claimBudgetAlert(level: MonthlyBudgetLevel, on date: Date) -> Bool
    func setCloudSyncEnabled(_ enabled: Bool)
    func queueCloudSync(_ snapshot: SubscriptionSyncSnapshot)
    func syncNow(_ snapshot: SubscriptionSyncSnapshot) async
}

/// Owns local persistence and the serialized CloudKit synchronization queue.
@MainActor
public final class SubscriptionRepository: SubscriptionRepositoryProtocol {
    public private(set) var isCloudSyncEnabled: Bool
    public private(set) var cloudSyncState: CloudSyncState
    public var onCloudSyncStateChange: (@MainActor (CloudSyncState) -> Void)?
    public var onSynchronized: (@MainActor (SubscriptionSyncSnapshot) -> Void)?

    private let defaults: UserDefaults
    private let storageKey: String
    private var cloudSync: CloudSubscriptionSync?
    private var pendingSnapshot: SubscriptionSyncSnapshot?
    private var isSyncing = false
    private var retryAttempt = 0
    private var retryTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "agentmeter.subscriptions.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        isCloudSyncEnabled = defaults.bool(forKey: "\(storageKey).icloud-enabled")
        cloudSyncState = isCloudSyncEnabled ? .syncing : .localOnly
    }

    public func loadLedger() -> SubscriptionLedger {
        SubscriptionLedger(
            subscriptions: decode([AISubscription].self, key: storageKey) ?? [],
            history: decode([SubscriptionHistoryEvent].self, key: "\(storageKey).history") ?? [],
            expenses: decode([AIExpense].self, key: "\(storageKey).expenses") ?? [],
            tombstones: decode([UUID: Date].self, key: "\(storageKey).tombstones") ?? [:]
        )
    }

    public func loadPreferences() -> SubscriptionStorePreferences {
        SubscriptionStorePreferences(
            displayCurrency: SpendDisplayCurrency(
                rawValue: defaults.string(forKey: "\(storageKey).display-currency") ?? "brl"
            ) ?? .brl,
            brlPerUSD: loadDecimal(key: "\(storageKey).brl-per-usd"),
            monthlyBudgetBRL: loadDecimal(key: "\(storageKey).monthly-budget"),
            isCloudSyncEnabled: isCloudSyncEnabled
        )
    }

    public func save(_ ledger: SubscriptionLedger) {
        encode(ledger.subscriptions, key: storageKey)
        encode(ledger.tombstones, key: "\(storageKey).tombstones")
        encode(ledger.history, key: "\(storageKey).history")
        encode(ledger.expenses, key: "\(storageKey).expenses")
    }

    public func saveDisplayCurrency(_ currency: SpendDisplayCurrency) {
        defaults.set(currency.rawValue, forKey: "\(storageKey).display-currency")
    }

    public func saveBRLPerUSD(_ rate: Decimal?) {
        saveDecimal(rate, key: "\(storageKey).brl-per-usd")
    }

    public func saveMonthlyBudgetBRL(_ amount: Decimal?) {
        saveDecimal(amount, key: "\(storageKey).monthly-budget")
    }

    public func claimBudgetAlert(level: MonthlyBudgetLevel, on date: Date = .now) -> Bool {
        let key = "\(storageKey).budget-alerts.\(Self.monthKey(date))"
        var fired = Set(defaults.stringArray(forKey: key) ?? [])
        guard fired.insert(String(level.rawValue)).inserted else { return false }
        defaults.set(Array(fired), forKey: key)
        return true
    }

    public func setCloudSyncEnabled(_ enabled: Bool) {
        isCloudSyncEnabled = enabled
        defaults.set(enabled, forKey: "\(storageKey).icloud-enabled")
        guard enabled else {
            retryTask?.cancel()
            retryTask = nil
            retryAttempt = 0
            pendingSnapshot = nil
            setCloudSyncState(.localOnly)
            return
        }
        setCloudSyncState(.syncing)
    }

    public func queueCloudSync(_ snapshot: SubscriptionSyncSnapshot) {
        guard isCloudSyncEnabled else { return }
        enqueue(snapshot)
        Task { await drainCloudQueue() }
    }

    public func syncNow(_ snapshot: SubscriptionSyncSnapshot) async {
        guard isCloudSyncEnabled else { return }
        enqueue(snapshot)
        await drainCloudQueue()
    }

    private func enqueue(_ snapshot: SubscriptionSyncSnapshot) {
        if let pendingSnapshot {
            self.pendingSnapshot = pendingSnapshot.merged(with: snapshot)
        } else {
            pendingSnapshot = snapshot
        }
    }

    private func drainCloudQueue() async {
        guard isCloudSyncEnabled, !isSyncing else { return }
        retryTask?.cancel()
        retryTask = nil
        isSyncing = true
        defer { isSyncing = false }

        let service = cloudSync ?? CloudSubscriptionSync()
        cloudSync = service

        while isCloudSyncEnabled, let candidate = pendingSnapshot {
            pendingSnapshot = nil
            setCloudSyncState(.syncing)
            do {
                let merged = try await service.synchronize(candidate)
                retryAttempt = 0
                if let queued = pendingSnapshot {
                    pendingSnapshot = merged.merged(with: queued)
                } else {
                    onSynchronized?(merged)
                    setCloudSyncState(.synced(.now))
                }
            } catch CloudSyncFailure.accountUnavailable {
                pendingSnapshot = nil
                setCloudSyncState(.unavailable)
                return
            } catch {
                if let queued = pendingSnapshot {
                    pendingSnapshot = candidate.merged(with: queued)
                } else {
                    pendingSnapshot = candidate
                }
                scheduleRetry()
                return
            }
        }
    }

    private func scheduleRetry() {
        guard retryAttempt < 3 else {
            setCloudSyncState(.failed)
            return
        }
        retryAttempt += 1
        let delay = min(pow(2, Double(retryAttempt)) * 5, 60)
        setCloudSyncState(.waitingToRetry(Date().addingTimeInterval(delay)))
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.drainCloudQueue()
        }
    }

    private func setCloudSyncState(_ state: CloudSyncState) {
        cloudSyncState = state
        onCloudSyncStateChange?(state)
    }

    private func encode<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func saveDecimal(_ value: Decimal?, key: String) {
        if let value {
            defaults.set(NSDecimalNumber(decimal: value).stringValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func loadDecimal(key: String) -> Decimal? {
        defaults.string(forKey: key).flatMap { Decimal(string: $0) }
    }

    private static func monthKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }
}
