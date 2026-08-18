import Foundation

/// Weather condition bucket the ambience layer renders, one per WMO
/// intensity band so every sky gets its own physics. Mapped from the
/// Open-Meteo WMO weather_code field — the mapping is a pure table so it
/// can be tested exhaustively without network access.
public enum WeatherCondition: String, Codable, Sendable, Equatable, CaseIterable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case heavyRain
    case freezingRain
    case snow
    case heavySnow
    case thunderstorm
    case severeThunderstorm

    /// WMO weather interpretation codes → condition bucket. Unknown codes
    /// (and out-of-range values) return nil: the caller decides the
    /// fallback, we never guess a condition.
    public static func from(wmoCode: Int) -> WeatherCondition? {
        switch wmoCode {
        case 0: .clear
        case 1, 2: .partlyCloudy
        case 3: .cloudy
        case 45, 48: .fog
        case 51, 53, 55: .drizzle
        case 56, 57: .freezingRain
        case 61, 63, 80: .rain
        case 65, 81, 82: .heavyRain
        case 66, 67: .freezingRain
        case 71, 73, 77, 85: .snow
        case 75, 86: .heavySnow
        case 95: .thunderstorm
        case 96, 99: .severeThunderstorm
        default: nil
        }
    }

    /// Precipitation kinds (rain/snow mixed and everything that falls).
    public var isPrecipitation: Bool {
        switch self {
        case .drizzle, .rain, .heavyRain, .freezingRain, .snow, .heavySnow,
             .thunderstorm, .severeThunderstorm:
            true
        case .clear, .partlyCloudy, .cloudy, .fog:
            false
        }
    }

    /// Overcast conditions that desaturate the sky palette.
    public var dimsSky: Bool {
        switch self {
        case .cloudy, .fog, .drizzle, .rain, .heavyRain, .freezingRain,
             .snow, .heavySnow, .thunderstorm, .severeThunderstorm:
            true
        case .clear, .partlyCloudy:
            false
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
    /// 10m wind speed in km/h — drives wind-blown particles and fast clouds.
    public var windSpeedKmh: Double
    /// Today's sunrise/sunset (local timezone, from the API) — feeds the
    /// procedural dawn/dusk sky gradient.
    public var sunrise: Date?
    public var sunset: Date?

    public init(
        condition: WeatherCondition,
        temperatureC: Double,
        isDay: Bool,
        city: String,
        capturedAt: Date,
        windSpeedKmh: Double = 0,
        sunrise: Date? = nil,
        sunset: Date? = nil
    ) {
        self.condition = condition
        self.temperatureC = temperatureC
        self.isDay = isDay
        self.city = city
        self.capturedAt = capturedAt
        self.windSpeedKmh = windSpeedKmh
        self.sunrise = sunrise
        self.sunset = sunset
    }
}
