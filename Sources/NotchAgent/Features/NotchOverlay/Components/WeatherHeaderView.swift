import SwiftUI

/// Pure formatting for the ambience layer — the view-level rules live here
/// so they are unit-testable (same pattern as Format/ProviderCardView).
enum WeatherFormat {
    static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func temperature(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°"
    }

    /// "H: 25° L: 9°" — nil-safe: with either bound missing (legacy cache,
    /// older payload) the whole line is dropped.
    static func highLow(max: Double?, min: Double?) -> String? {
        guard let max, let min else { return nil }
        return "H: \(temperature(max)) L: \(temperature(min))"
    }

    static func symbol(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain: "cloud.sleet.fill"
        case .snow: "cloud.snow.fill"
        case .heavySnow: "snowflake"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .severeThunderstorm: "cloud.bolt.fill"
        }
    }
}

/// The Apple Weather hierarchy, shrunk to the panel: clock + resolved city
/// on the small top line, the giant current temperature, then condition +
/// high/low. Compact enough that the Now page keeps its cards — it
/// whispers, it never shouts.
struct WeatherHeaderView: View {
    let phase: WeatherStore.Phase

    var body: some View {
        Group {
            switch phase {
            case .fresh(let snapshot):
                VStack(spacing: 2) {
                    HStack {
                        TimelineView(.periodic(from: .now, by: 30)) { timeline in
                            Text(WeatherFormat.clock(timeline.date))
                                .font(Theme.numeral(10))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        // The resolved city is always visible — precision is
                        // checkable at a glance, never silently wrong. Capped
                        // so a long name can never squeeze the clock.
                        Text(snapshot.city)
                            .font(Theme.body(9, weight: .medium))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 220, alignment: .trailing)
                    }
                    Text(WeatherFormat.temperature(snapshot.temperatureC))
                        .font(Theme.numeral(30))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 5) {
                        Image(systemName: WeatherFormat.symbol(for: snapshot.condition))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                        Text(snapshot.condition.label)
                            .font(Theme.body(10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        if let highLow = WeatherFormat.highLow(
                            max: snapshot.temperatureMaxC,
                            min: snapshot.temperatureMinC
                        ) {
                            Text("· \(highLow)")
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                }
            case .unavailable:
                // Local clock only — it needs no network.
                HStack {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        Text(WeatherFormat.clock(timeline.date))
                            .font(Theme.numeral(10))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                }
            }
        }
    }
}
