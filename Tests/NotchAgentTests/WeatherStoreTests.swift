import XCTest
@testable import NotchAgent

@MainActor
final class WeatherStoreTests: XCTestCase {
    private final class MockWeather: WeatherFetching, @unchecked Sendable {
        var fetchCalls = 0
        var geocodeCalls = 0
        var ipCalls = 0
        var shouldThrow = false

        func fetch(lat: Double, lon: Double, city: String) async throws -> WeatherSnapshot {
            fetchCalls += 1
            if shouldThrow { throw WeatherError.badPayload }
            return WeatherSnapshot(condition: .rain, temperatureC: 24, isDay: true, city: city, capturedAt: .now)
        }

        func geocode(city: String) async throws -> (lat: Double, lon: Double, name: String) {
            geocodeCalls += 1
            if shouldThrow { throw WeatherError.badPayload }
            return (-8.05, -34.9, "Recife, BR")
        }

        func resolveByIP() async throws -> (lat: Double, lon: Double, name: String) {
            ipCalls += 1
            if shouldThrow { throw WeatherError.badPayload }
            return (-23.55, -46.63, "São Paulo, BR")
        }
    }

    private func makeStore(
        defaults: UserDefaults,
        mock: MockWeather = MockWeather(),
        city: String? = nil,
        enabled: Bool = true,
        persistedLat: Double? = nil,
        persistedLon: Double? = nil,
        persistedCity: String? = nil
    ) -> (WeatherStore, PreferencesStore) {
        let preferences = PreferencesStore(defaults: defaults)
        preferences.settings.weatherEnabled = enabled
        preferences.settings.weatherCity = city
        preferences.settings.weatherLat = persistedLat
        preferences.settings.weatherLon = persistedLon
        preferences.settings.weatherCityResolved = persistedCity
        let store = WeatherStore(settings: preferences, defaults: defaults, service: mock)
        return (store, preferences)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "weather-test-\(UUID().uuidString)")!
    }

    func testFreshCacheSkipsNetwork() async throws {
        let defaults = freshDefaults()
        let mock = MockWeather()
        let (store, _) = makeStore(defaults: defaults, mock: mock)
        let cached = WeatherSnapshot(condition: .clear, temperatureC: 30, isDay: true, city: "X", capturedAt: .now)
        defaults.set(try JSONEncoder().encode(cached), forKey: "weather.snapshot")

        await store.refreshIfNeeded()

        XCTAssertEqual(mock.fetchCalls, 0)
        XCTAssertEqual(mock.ipCalls, 0)
        guard case .fresh(let snap) = store.phase else { return XCTFail("expected .fresh") }
        XCTAssertEqual(snap, cached)
    }

    func testStaleCacheRefetchesAndPersists() async throws {
        let defaults = freshDefaults()
        let mock = MockWeather()
        let (store, _) = makeStore(defaults: defaults, mock: mock, persistedLat: -23.55, persistedLon: -46.63, persistedCity: "São Paulo, BR")
        let stale = WeatherSnapshot(condition: .clear, temperatureC: 10, isDay: true, city: "X", capturedAt: Date().addingTimeInterval(-3600))
        defaults.set(try JSONEncoder().encode(stale), forKey: "weather.snapshot")

        await store.refreshIfNeeded()

        XCTAssertEqual(mock.fetchCalls, 1)
        XCTAssertEqual(mock.ipCalls, 0, "persisted lat/lon must skip geo-IP")
        guard case .fresh(let snap) = store.phase else { return XCTFail("expected .fresh") }
        XCTAssertEqual(snap.city, "São Paulo, BR")
        XCTAssertNotNil(WeatherStore.decodeCache(defaults.object(forKey: "weather.snapshot") as? Data))
    }

    func testManualCityBeatsPersistedLocation() async throws {
        let defaults = freshDefaults()
        let mock = MockWeather()
        let (store, _) = makeStore(defaults: defaults, mock: mock, city: "Recife", persistedLat: -23.55, persistedLon: -46.63, persistedCity: "São Paulo, BR")

        await store.refreshIfNeeded()

        XCTAssertEqual(mock.geocodeCalls, 1)
        XCTAssertEqual(mock.fetchCalls, 1)
        guard case .fresh(let snap) = store.phase else { return XCTFail("expected .fresh") }
        XCTAssertEqual(snap.city, "Recife, BR")
    }

    func testFirstRunResolvesByIPAndPersists() async throws {
        let defaults = freshDefaults()
        let mock = MockWeather()
        let (store, preferences) = makeStore(defaults: defaults, mock: mock)

        await store.refreshIfNeeded()

        XCTAssertEqual(mock.ipCalls, 1)
        XCTAssertEqual(mock.fetchCalls, 1)
        XCTAssertEqual(preferences.settings.weatherLat, -23.55)
        XCTAssertEqual(preferences.settings.weatherLon, -46.63)
        XCTAssertEqual(preferences.settings.weatherCityResolved, "São Paulo, BR")
    }

    func testNetworkFailureIsUnavailable() async throws {
        let defaults = freshDefaults()
        let mock = MockWeather()
        mock.shouldThrow = true
        let (store, _) = makeStore(defaults: defaults, mock: mock, persistedLat: -23.55, persistedLon: -46.63)

        await store.refreshIfNeeded()

        XCTAssertEqual(store.phase, .unavailable)
    }

    func testDisabledIsUnavailableWithoutNetwork() async throws {
        let defaults = freshDefaults()
        let mock = MockWeather()
        let (store, _) = makeStore(defaults: defaults, mock: mock, enabled: false)

        await store.refreshIfNeeded()

        XCTAssertEqual(store.phase, .unavailable)
        XCTAssertEqual(mock.fetchCalls, 0)
        XCTAssertEqual(mock.ipCalls, 0)
        XCTAssertEqual(mock.geocodeCalls, 0)
    }

    func testStopClearsPhase() async throws {
        let defaults = freshDefaults()
        let mock = MockWeather()
        let (store, _) = makeStore(defaults: defaults, mock: mock, persistedLat: -23.55, persistedLon: -46.63)
        await store.refreshIfNeeded()
        guard case .fresh = store.phase else { return XCTFail("expected .fresh") }

        store.stop()

        XCTAssertEqual(store.phase, .unavailable)
    }

    func testDecodeCacheHandlesGarbage() {
        XCTAssertNil(WeatherStore.decodeCache(Data("garbage".utf8)))
        XCTAssertNil(WeatherStore.decodeCache(nil))
    }
}
