import Foundation
import AgentMeterCore

/// Composition root: builds and wires every service exactly once.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let preferences: PreferencesStore
    let store: UsageStore
    let providers: [any UsageProvider]
    let snapshotStore: SnapshotStore
    let historyStore: HistoryStore
    let scheduler: RefreshScheduler
    let notchViewModel: NotchViewModel
    let router: WindowRouter
    let spending: SubscriptionStore
    let desk: NotchAgentDeskCoordinator
    let appUpdates: AppUpdateController
    let notifications = NotificationService()
    private(set) var notchController: NotchWindowController?
    private var exchangeRateTask: Task<Void, Never>?

    private init() {
        preferences = PreferencesStore()
        store = UsageStore(preferences: preferences)
        providers = [ClaudeProvider(), CodexProvider(), GeminiProvider(), APIAccountProvider()]
        snapshotStore = SnapshotStore()
        historyStore = HistoryStore()
        scheduler = RefreshScheduler(
            providers: providers,
            store: store,
            snapshotStore: snapshotStore,
            historyStore: historyStore
        )
        notchViewModel = NotchViewModel()
        router = WindowRouter()
        spending = SubscriptionStore()
        desk = NotchAgentDeskCoordinator(store: store)
        appUpdates = AppUpdateController()
        router.environment = self
        desk.onConnectionPhaseChange = { [weak self] phase in
            guard let self,
                  phase == .connected || phase == .incompatible,
                  !self.preferences.settings.notchAgentDeskOnboardingCompleted
            else { return }
            self.router.openSettings()
        }
        spending.onMonthlyBudgetAlert = { [notifications, preferences] alert in
            notifications.postBudget(alert, settings: preferences.settings)
        }
        store.onAlert = { [notifications, preferences] alert in
            notifications.post(alert, settings: preferences.settings)
        }
        store.onRestore = { [notifications, preferences] moment in
            notifications.postRestored(moment, settings: preferences.settings)
        }
    }

    func bootstrap(startScheduler: Bool = true, deskMirroringOverride: Bool? = nil) {
        Log.app.info("bootstrap: \(self.providers.count) providers")
        for provider in providers {
            let installation = provider.detectInstallation()
            Log.providers.info("\(provider.id.rawValue, privacy: .public): \(String(describing: installation), privacy: .public)")
        }

        let controller = NotchWindowController(viewModel: notchViewModel, store: store, router: router, spending: spending)
        notchController = controller
        controller.show()

        Task {
            let persisted = await snapshotStore.load()
            store.restore(persisted)
            if startScheduler {
                scheduler.start()
            }
        }
        startExchangeRateRefresh()
        // Discovery and hardware telemetry are automatic. The preference only
        // controls whether sanitized usage snapshots are mirrored to the Desk.
        desk.start(mirroringEnabled: deskMirroringOverride ?? preferences.settings.notchAgentDeskEnabled)
        store.record(UsageEvent(kind: .info, message: "NotchAgent started"))
    }

    private func startExchangeRateRefresh() {
        exchangeRateTask?.cancel()
        exchangeRateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let rate = await BRLExchangeRateService.shared.latestUSDToBRL() {
                    self.spending.setBRLPerUSD(rate)
                }
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func applyThemeMode() {
        let appearance = preferences.settings.themeMode.nsAppearance
        notchController?.applyAppearance(appearance)
        router.applyAppearance(appearance)
    }

    func applyNotchAgentDeskEnabled() {
        desk.setMirroringEnabled(preferences.settings.notchAgentDeskEnabled)
    }
}
