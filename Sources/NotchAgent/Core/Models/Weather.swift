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

    /// Human condition name for the header line ("Clear", "Fog", …) —
    /// English copy, matching the rest of the panel UI.
    public var label: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .heavyRain: "Heavy rain"
        case .freezingRain: "Freezing rain"
        case .snow: "Snow"
        case .heavySnow: "Heavy snow"
        case .thunderstorm: "Thunderstorm"
        case .severeThunderstorm: "Severe thunderstorm"
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
    /// Today's high/low (from the daily forecast) — the Apple-style
    /// "H: x° L: y°" line. Optional: legacy caches and older payloads
    /// simply omit the line.
    public var temperatureMaxC: Double?
    public var temperatureMinC: Double?

    public init(
        condition: WeatherCondition,
        temperatureC: Double,
        isDay: Bool,
        city: String,
        capturedAt: Date,
        windSpeedKmh: Double = 0,
        sunrise: Date? = nil,
        sunset: Date? = nil,
        temperatureMaxC: Double? = nil,
        temperatureMinC: Double? = nil
    ) {
        self.condition = condition
        self.temperatureC = temperatureC
        self.isDay = isDay
        self.city = city
        self.capturedAt = capturedAt
        self.windSpeedKmh = windSpeedKmh
        self.sunrise = sunrise
        self.sunset = sunset
        self.temperatureMaxC = temperatureMaxC
        self.temperatureMinC = temperatureMinC
    }

    /// Manual decode with defaults: caches written before wind/sun fields
    /// existed must still load (the store then refreshes them naturally).
    private enum CodingKeys: String, CodingKey {
        case condition, temperatureC, isDay, city, capturedAt
        case windSpeedKmh, sunrise, sunset, temperatureMaxC, temperatureMinC
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        condition = try container.decode(WeatherCondition.self, forKey: .condition)
        temperatureC = try container.decode(Double.self, forKey: .temperatureC)
        isDay = try container.decode(Bool.self, forKey: .isDay)
        city = try container.decode(String.self, forKey: .city)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        windSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .windSpeedKmh) ?? 0
        sunrise = try container.decodeIfPresent(Date.self, forKey: .sunrise)
        sunset = try container.decodeIfPresent(Date.self, forKey: .sunset)
        temperatureMaxC = try container.decodeIfPresent(Double.self, forKey: .temperatureMaxC)
        temperatureMinC = try container.decodeIfPresent(Double.self, forKey: .temperatureMinC)
    }
}
