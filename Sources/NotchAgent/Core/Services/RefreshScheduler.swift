import AppKit
import Foundation

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
    private var tickInFlight = false

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
        // two ticks interleaved (double fetches, flapping refresh states).
        guard !tickInFlight else { return }
        tickInFlight = true
        defer { tickInFlight = false }
        let settings = store.settings
        for provider in providers {
            store.markRefreshing(provider.id)
        }

        let results = await withTaskGroup(
            of: (ProviderID, Result<UsageSnapshot, Error>).self,
            returning: [(ProviderID, Result<UsageSnapshot, Error>)].self
        ) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return (provider.id, .success(try await provider.fetchSnapshot(settings: settings)))
                    } catch {
                        return (provider.id, .failure(error))
                    }
                }
            }
            var collected: [(ProviderID, Result<UsageSnapshot, Error>)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for (providerID, result) in results {
            switch result {
            case .success(let snapshot):
                store.apply(snapshot)
                await historyStore.record(snapshot)
                Log.refresh.debug("refreshed \(providerID.rawValue, privacy: .public): \(snapshot.health.rawValue, privacy: .public)")
            case .failure(let error):
                store.applyFailure(providerID, error: error.localizedDescription)
                Log.refresh.error("refresh failed \(providerID.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        await snapshotStore.save(store.snapshots)
        await historyStore.flush()
        await updateSparklines()
        store.setIncident(await statusPage.activeIncident())
    }

    private func updateSparklines() async {
        for provider in providers {
            let points = await historyStore.series(for: provider.id, lastHours: 24)
            store.updateSparkline(provider.id, values: points.map { Double($0.sessionTokens) })
        }
    }
}
