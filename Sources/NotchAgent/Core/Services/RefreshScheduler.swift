import AppKit
import Foundation

/// Coalesces repeated refresh clicks without dropping a forced refresh that
/// arrives while the periodic loop is still running.
struct RefreshRequestQueue {
    private(set) var isRunning = false
    private var forcedRefreshPending = false

    mutating func begin(force: Bool) -> Bool {
        guard !isRunning else {
            if force { forcedRefreshPending = true }
            return false
        }
        isRunning = true
        if force { forcedRefreshPending = false }
        return true
    }

    /// Returns true when one forced refresh must run immediately afterward.
    mutating func finish() -> Bool {
        isRunning = false
        return forcedRefreshPending
    }
}

struct RefreshGenerationTracker {
    private(set) var counter: UInt64 = 0
    private var providerGeneration: [ProviderID: UInt64] = [:]
    private var accountGeneration: [UUID: UInt64] = [:]

    mutating func beginProvider(_ provider: ProviderID) -> UInt64 {
        counter &+= 1
        providerGeneration[provider] = counter
        return counter
    }

    mutating func beginAccount(_ accountID: UUID) -> UInt64 {
        counter &+= 1
        accountGeneration[accountID] = counter
        return counter
    }

    func acceptsProvider(_ provider: ProviderID, generation: UInt64) -> Bool {
        providerGeneration[provider] == generation
    }

    func acceptsAccount(_ accountID: UUID, generation: UInt64) -> Bool {
        accountGeneration[accountID] == generation
    }

    func accountIsNewer(_ accountID: UUID, than generation: UInt64) -> Bool {
        (accountGeneration[accountID] ?? 0) > generation
    }

    mutating func didApplyProvider(
        _ provider: ProviderID,
        generation: UInt64,
        accountIDs: [UUID] = []
    ) {
        guard acceptsProvider(provider, generation: generation) else { return }
        for accountID in accountIDs {
            if !accountIsNewer(accountID, than: generation) {
                accountGeneration[accountID] = generation
            }
        }
    }
}

/// Central refresh loop: fans out to all providers concurrently, feeds the
/// store, persists snapshots/history. One scheduler owns all polling — no
/// provider ever refreshes itself.
@MainActor
final class RefreshScheduler {
    private let providers: [any UsageProvider]
    private let store: UsageStore
    private let snapshotStore: SnapshotStore
    private let historyStore: HistoryStore
    private let statusPage = StatusPageService()
    private var loopTask: Task<Void, Never>?
    private var refreshQueue = RefreshRequestQueue()
    private var generations = RefreshGenerationTracker()

    init(
        providers: [any UsageProvider],
        store: UsageStore,
        snapshotStore: SnapshotStore,
        historyStore: HistoryStore
    ) {
        self.providers = providers
        self.store = store
        self.snapshotStore = snapshotStore
        self.historyStore = historyStore
    }

    func start() {
        guard loopTask == nil else { return }
        Log.refresh.info("scheduler started")

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let interval = max(15, self.store.settings.refreshIntervalSeconds)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func refreshNow() {
        Task { await tick(force: true) }
    }

    func refreshAPIAccount(_ accountID: UUID) {
        guard let account = store.settings.apiAccounts.first(where: {
            $0.id == accountID && $0.enabled
        }), let provider = providers.first(where: {
            $0.id == .apiAccounts
        }) as? APIAccountProvider else { return }

        let generation = generations.beginAccount(accountID)
        store.markAccountRefreshing(accountID)
        Task { [weak self] in
            guard let self else { return }
            let usage = await provider.fetchAccountUsage(for: account)
            guard self.generations.acceptsAccount(accountID, generation: generation) else {
                Log.refresh.debug("discarded superseded account refresh")
                return
            }

            var snapshot = self.store.snapshots[.apiAccounts]
                ?? UsageSnapshot(provider: .apiAccounts, health: .noData)
            var usages = snapshot.accountUsage ?? []
            if let index = usages.firstIndex(where: { $0.accountID == accountID }) {
                usages[index] = usage
            } else {
                usages.append(usage)
            }
            snapshot.accountUsage = usages
            snapshot.capturedAt = Date()
            snapshot.health = usages.allSatisfy {
                $0.readStatus == .updated || $0.readStatus == .partial
            } ? .ok : .degraded
            snapshot.note = usages.map(\.summary).joined(separator: " · ")
            self.store.apply(snapshot, updatingAccountIDs: [accountID])
            await self.historyStore.record(snapshot)
            await self.snapshotStore.save(self.store.snapshots)
            await self.historyStore.flush()
        }
    }

    /// Stop + start: applies a changed refresh interval immediately instead of
    /// waiting out the previous (possibly 5-minute) sleep.
    func restart() {
        stop()
        start()
    }

    @objc private func systemDidWake() {
        // Respect a user-initiated pause — waking the lid must not spend probes.
        guard !store.isPaused else { return }
        Log.refresh.info("system woke — refreshing")
        refreshNow()
    }

    private func tick(force: Bool = false) async {
        if store.isPaused && !force {
            return
        }
        // A wake-triggered forced tick may race the periodic loop — never run
        // two ticks interleaved. Forced clicks are queued instead of dropped.
        guard refreshQueue.begin(force: force) else { return }
        let settings = store.settings
        for provider in providers {
            store.markRefreshing(provider.id)
        }

        let results = await withTaskGroup(
            of: (ProviderID, UInt64, Result<UsageSnapshot, Error>).self,
            returning: [(ProviderID, UInt64, Result<UsageSnapshot, Error>)].self
        ) { group in
            for provider in providers {
                let generation = generations.beginProvider(provider.id)
                group.addTask {
                    do {
                        if force {
                            await provider.invalidateCache()
                        }
                        return (
                            provider.id,
                            generation,
                            .success(try await provider.fetchSnapshot(settings: settings))
                        )
                    } catch {
                        return (provider.id, generation, .failure(error))
                    }
                }
            }
            var collected: [(ProviderID, UInt64, Result<UsageSnapshot, Error>)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for (providerID, generation, result) in results {
            guard generations.acceptsProvider(providerID, generation: generation) else {
                Log.refresh.debug("discarded superseded provider refresh")
                continue
            }
            switch result {
            case .success(var snapshot):
                var updatedAccountIDs: Set<UUID>?
                if providerID == .apiAccounts {
                    let current = Dictionary(
                        uniqueKeysWithValues: (store.snapshots[.apiAccounts]?.accountUsage ?? [])
                            .map { ($0.accountID, $0) }
                    )
                    var accepted = Set<UUID>()
                    snapshot.accountUsage = (snapshot.accountUsage ?? []).compactMap { usage in
                        guard generations.accountIsNewer(usage.accountID, than: generation) else {
                            accepted.insert(usage.accountID)
                            return usage
                        }
                        return current[usage.accountID]
                    }
                    updatedAccountIDs = accepted
                }
                store.apply(snapshot, updatingAccountIDs: updatedAccountIDs)
                generations.didApplyProvider(
                    providerID,
                    generation: generation,
                    accountIDs: Array(updatedAccountIDs ?? Set(snapshot.accountUsage?.map(\.accountID) ?? []))
                )
                await historyStore.record(snapshot)
                Log.refresh.debug("refreshed \(providerID.rawValue, privacy: .public): \(snapshot.health.rawValue, privacy: .public)")
            case .failure(let error):
                let accountIDs = providerID == .apiAccounts
                    ? Set(store.settings.apiAccounts.filter {
                        $0.enabled && !generations.accountIsNewer($0.id, than: generation)
                    }.map(\.id))
                    : nil
                store.applyFailure(
                    providerID,
                    error: error.localizedDescription,
                    updatingAccountIDs: accountIDs
                )
                Log.refresh.error("refresh failed \(providerID.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        await snapshotStore.save(store.snapshots)

        // Insights da sessão ativa: um payload por provider, computado uma vez
        // por tick — as views só renderizam (nunca recalculam).
        let payloads = await SessionInsightsEngine.refresh(
            snapshots: store.snapshots,
            dataProvider: LiveSessionDataProvider()
        )
        store.setPayloads(payloads)

        await historyStore.flush()
        await updateSparklines()
        store.setIncident(await statusPage.activeIncident())

        let runQueuedRefresh = refreshQueue.finish()
        if runQueuedRefresh {
            await tick(force: true)
        }
    }

    private func updateSparklines() async {
        for provider in providers {
            let points = await historyStore.series(for: provider.id, lastHours: 24)
            store.updateSparkline(provider.id, values: points.map { Double($0.sessionTokens) })
        }
    }
}
