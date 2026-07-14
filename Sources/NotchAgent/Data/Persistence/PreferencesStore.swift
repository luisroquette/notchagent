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
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
