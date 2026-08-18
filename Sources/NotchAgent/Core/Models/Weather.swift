import Foundation

/// Weather condition bucket the ambience layer renders. Mapped from the
/// Open-Meteo WMO weather_code field — the mapping is a pure table so it
/// can be tested exhaustively without network access.
public enum WeatherCondition: String, Codable, Sendable, Equatable {
    case clear
    case partlyCloudy
    case cloudy
    case rain
    case storm
    case snow

    /// WMO weather interpretation codes → condition bucket. Unknown codes
    /// (and out-of-range values) return nil: the caller decides the
    /// fallback, we never guess a condition.
    public static func from(wmoCode: Int) -> WeatherCondition? {
        switch wmoCode {
        case 0: .clear
        case 1, 2: .partlyCloudy
        case 3, 45, 48: .cloudy
        case 51...67, 80...82: .rain
        case 71...77, 85, 86: .snow
        case 95, 96, 99: .storm
        default: nil
        }
    }
}

/// One point-in-time weather reading, cached locally. Small enough to live
/// in UserDefaults as JSON.
public struct WeatherSnapshot: Codable, Sendable, Equatable {
    public var condition: WeatherCondition
    public var temperatureC: Double
    public var isDay: Bool
    public var city: String
    public var capturedAt: Date

    public init(condition: WeatherCondition, temperatureC: Double, isDay: Bool, city: String, capturedAt: Date) {
        self.condition = condition
        self.temperatureC = temperatureC
        self.isDay = isDay
        self.city = city
        self.capturedAt = capturedAt
    }
}
