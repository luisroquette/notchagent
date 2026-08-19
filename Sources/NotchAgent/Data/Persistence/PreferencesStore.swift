import Foundation
import Observation

/// Observable wrapper over `AppSettings`, persisted as a JSON blob in UserDefaults.
@MainActor
@Observable
final class PreferencesStore {
    private static let key = "app.settings.v1"

    var settings: AppSettings {
        didSet { persist() }
    }

    /// The app's preferences domain, pinned EXPLICITLY. REGRESSÃO: a bare
    /// `swift run` has no bundle id, so UserDefaults.standard lands on the
    /// executable's own domain — every test instance silently ignored the
    /// installed app's settings (probe off, no consent) while the installed
    /// app worked. The suiteName domain is the SAME domain the installed
    /// .app's standard defaults use, so both packaging worlds read and
    /// write the one true settings blob.
    static let defaultStore: UserDefaults = {
        UserDefaults(suiteName: "br.com.lfrprojects.notchagent") ?? .standard
    }()

    init(defaults: UserDefaults = PreferencesStore.defaultStore) {
        var loaded: AppSettings
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            loaded = decoded
        } else {
            loaded = AppSettings()
        }
        loaded.ensureWebSubscriptionAccountsIfNeeded()
        settings = loaded
        if let data = try? JSONEncoder().encode(loaded) {
            defaults.set(data, forKey: Self.key)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
