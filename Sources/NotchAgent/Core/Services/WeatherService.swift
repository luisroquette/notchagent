import Foundation

enum WeatherError: Error {
    case invalidURL
    case http
    case badPayload
}

/// The one network seam of the ambience layer. Mock this in tests; the
/// store never talks to URLSession directly.
protocol WeatherFetching: Sendable {
    func fetch(lat: Double, lon: Double, city: String) async throws -> WeatherSnapshot
    func geocode(city: String) async throws -> (lat: Double, lon: Double, name: String)
    func resolveByIP() async throws -> (lat: Double, lon: Double, name: String)
}

/// Open-Meteo (forecast + geocoding, free, keyless) and ipwho.is (geo-IP,
/// HTTPS, keyless). Parses are pure static functions so every table edge
/// is testable without a socket.
actor WeatherService: WeatherFetching {
    static let shared = WeatherService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(lat: Double, lon: Double, city: String) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else { throw WeatherError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.http
        }
        guard let snapshot = Self.snapshot(fromOpenMeteo: data, city: city, now: Date()) else {
            throw WeatherError.badPayload
        }
        return snapshot
    }

    func geocode(city: String) async throws -> (lat: Double, lon: Double, name: String) {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "pt"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { throw WeatherError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.http
        }
        guard let place = Self.place(fromGeocoding: data) else { throw WeatherError.badPayload }
        return place
    }

    func resolveByIP() async throws -> (lat: Double, lon: Double, name: String) {
        guard let url = URL(string: "https://ipwho.is/") else { throw WeatherError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.http
        }
        guard let place = Self.place(fromIP: data) else { throw WeatherError.badPayload }
        return place
    }

    // MARK: Pure parses

    static func snapshot(fromOpenMeteo data: Data, city: String, now: Date) -> WeatherSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any],
              let temperature = current["temperature_2m"] as? Double,
              let code = current["weather_code"] as? Int,
              let condition = WeatherCondition.from(wmoCode: code)
        else { return nil }
        let isDay = (current["is_day"] as? Int ?? 1) == 1
        return WeatherSnapshot(condition: condition, temperatureC: temperature, isDay: isDay, city: city, capturedAt: now)
    }

    static func place(fromGeocoding data: Data) -> (Double, Double, String)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let first = results.first,
              let lat = first["latitude"] as? Double,
              let lon = first["longitude"] as? Double,
              let name = first["name"] as? String
        else { return nil }
        let label = (first["country"] as? String).map { "\(name), \($0)" } ?? name
        return (lat, lon, label)
    }

    static func place(fromIP data: Data) -> (Double, Double, String)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["success"] as? Bool) == true,
              let lat = root["latitude"] as? Double,
              let lon = root["longitude"] as? Double,
              let city = root["city"] as? String
        else { return nil }
        let label = (root["country_code"] as? String).map { "\(city), \($0)" } ?? city
        return (lat, lon, label)
    }
}
