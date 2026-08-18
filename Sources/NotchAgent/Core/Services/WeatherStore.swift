import Foundation
import Observation

/// Orchestrates the ambience layer: cache (UserDefaults, 30 min TTL),
/// one-time location resolution (manual city > persisted > geo-IP) and a
/// 30-minute refresh loop. Any failure lands on `.unavailable` — the UI
/// then renders exactly as it did before this feature existed.
@MainActor
@Observable
final class WeatherStore {
    enum Phase: Equatable {
        case fresh(WeatherSnapshot)
        case unavailable
    }

    private(set) var phase: Phase = .unavailable

    private let settings: PreferencesStore
    private let defaults: UserDefaults
    private let service: any WeatherFetching
    private let cacheKey = "weather.snapshot"
    private let maxAge: TimeInterval = 30 * 60
    private var loopTask: Task<Void, Never>?

    init(
        settings: PreferencesStore,
        defaults: UserDefaults = .standard,
        service: any WeatherFetching = WeatherService.shared
    ) {
        self.settings = settings
        self.defaults = defaults
        self.service = service
    }

    func refreshIfNeeded(now: Date = .now) async {
        guard settings.settings.weatherEnabled else {
            phase = .unavailable
            return
        }
        if let cached = Self.decodeCache(defaults.object(forKey: cacheKey) as? Data),
           now.timeIntervalSince(cached.capturedAt) < maxAge {
            phase = .fresh(cached)
            return
        }
        do {
            let place = try await resolvePlace()
            let snapshot = try await service.fetch(lat: place.lat, lon: place.lon, city: place.name)
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: cacheKey)
            }
            phase = .fresh(snapshot)
        } catch {
            phase = .unavailable
        }
    }

    func start() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            await self?.refreshIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                guard !Task.isCancelled else { return }
                await self?.refreshIfNeeded()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        phase = .unavailable
    }

    // MARK: Location resolution

    private func resolvePlace() async throws -> (lat: Double, lon: Double, name: String) {
        if let city = settings.settings.weatherCity,
           !city.trimmingCharacters(in: .whitespaces).isEmpty {
            return try await service.geocode(city: city)
        }
        if let lat = settings.settings.weatherLat, let lon = settings.settings.weatherLon {
            return (lat, lon, settings.settings.weatherCityResolved ?? "")
        }
        // First successful resolution persists — geo-IP runs once in the
        // app's lifetime.
        let place = try await service.resolveByIP()
        settings.settings.weatherLat = place.lat
        settings.settings.weatherLon = place.lon
        settings.settings.weatherCityResolved = place.name
        return place
    }

    // MARK: Cache

    static func decodeCache(_ data: Data?) -> WeatherSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }
}
