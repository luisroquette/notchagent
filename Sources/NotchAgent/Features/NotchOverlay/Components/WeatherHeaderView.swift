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

/// One thin line at the top of the Now page: local clock (always, it needs
/// no network) and, when a fresh snapshot exists, condition icon + current
/// temperature. Deliberately small — it whispers, it never shouts.
struct WeatherHeaderView: View {
    let phase: WeatherStore.Phase

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                Text(WeatherFormat.clock(timeline.date))
                    .font(Theme.numeral(12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            if case .fresh(let snapshot) = phase {
                // The resolved city is always visible — precision is
                // checkable at a glance, never silently wrong. Capped so a
                // long name can never squeeze the clock.
                Text(snapshot.city)
                    .font(Theme.body(8.5, weight: .medium))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 130, alignment: .trailing)
                Image(systemName: WeatherFormat.symbol(for: snapshot.condition))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                Text(WeatherFormat.temperature(snapshot.temperatureC))
                    .font(Theme.numeral(12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
