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

    init(defaults: UserDefaults = .standard) {
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
