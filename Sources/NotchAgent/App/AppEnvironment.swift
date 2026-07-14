import Foundation

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
    let notifications = NotificationService()
    private(set) var notchController: NotchWindowController?

    private init() {
        preferences = PreferencesStore()
        store = UsageStore(preferences: preferences)
        providers = [ClaudeProvider(), CodexProvider(), GeminiProvider()]
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
        router.environment = self
        store.onAlert = { [notifications, preferences] alert in
            notifications.post(alert, settings: preferences.settings)
        }
        store.onRestore = { [notifications, preferences] moment in
            notifications.postRestored(moment, settings: preferences.settings)
        }
    }

    func bootstrap() {
        Log.app.info("bootstrap: \(self.providers.count) providers")
        for provider in providers {
            let installation = provider.detectInstallation()
            Log.providers.info("\(provider.id.rawValue, privacy: .public): \(String(describing: installation), privacy: .public)")
        }

        let controller = NotchWindowController(viewModel: notchViewModel, store: store, router: router)
        notchController = controller
        controller.show()

        Task {
            let persisted = await snapshotStore.load()
            store.restore(persisted)
            scheduler.start()
        }
        store.record(UsageEvent(kind: .info, message: "NotchAgent started"))
    }

    func applyThemeMode() {
        let appearance = preferences.settings.themeMode.nsAppearance
        notchController?.applyAppearance(appearance)
        router.applyAppearance(appearance)
    }
}
