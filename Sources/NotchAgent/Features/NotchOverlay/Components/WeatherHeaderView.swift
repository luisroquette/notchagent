import SwiftUI

/// Pure formatting for the weather strip — the view-level rules live here
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
}

/// Procedural 8-bit glyphs for the weather strip — one grid per condition,
/// day/night aware. Same drawing pattern as PixelGlyph: 0 empty, 1 body.
/// REFACTOR 19/08/2026: replaces the full-panel sky ambience (SF Symbols +
/// gradient) with a minimal strip confined to the top of the notch.
enum WeatherPixelArt {
    static func grid(for condition: WeatherCondition, isDay: Bool) -> [[Int]] {
        switch condition {
        case .clear: isDay ? sun : moon
        case .partlyCloudy: isDay ? sunCloud : moonCloud
        case .cloudy: cloud
        case .fog: fog
        case .drizzle: drizzle
        case .rain: rain
        case .heavyRain: heavyRain
        case .freezingRain: freezingRain
        case .snow: snow
        case .heavySnow: heavySnow
        case .thunderstorm: thunderstorm
        case .severeThunderstorm: severeThunderstorm
        }
    }

    static let sun: [[Int]] = [
        [0, 0, 0, 1, 1, 0, 0, 0],
        [0, 0, 0, 1, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 1, 1, 1, 1, 1, 0, 0],
        [0, 1, 1, 1, 1, 1, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 0, 0, 1, 1, 0, 0, 0],
        [0, 0, 0, 1, 1, 0, 0, 0],
    ]

    static let moon: [[Int]] = [
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [0, 1, 1, 1, 1, 1, 0, 0],
        [0, 1, 1, 1, 1, 1, 0, 0],
        [0, 1, 1, 1, 1, 1, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
    ]

    static let sunCloud: [[Int]] = [
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [1, 1, 1, 1, 0, 0, 0, 0],
        [0, 0, 1, 1, 1, 1, 1, 0],
        [0, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
    ]

    static let moonCloud: [[Int]] = [
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 0, 0, 0, 0],
        [0, 0, 1, 1, 1, 1, 1, 0],
        [0, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
    ]

    static let cloud: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [0, 1, 1, 1, 1, 1, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
    ]

    static let fog: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 1, 0, 1, 0, 1, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
    ]

    static let drizzle: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 1, 0, 0, 0, 1, 0, 0],
        [0, 1, 0, 0, 0, 1, 0, 0],
    ]

    static let rain: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 1, 0, 1, 0, 1, 0, 0],
        [0, 1, 0, 1, 0, 1, 0, 0],
    ]

    static let heavyRain: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 0, 1, 1, 0, 1, 1, 0],
        [1, 0, 1, 1, 0, 1, 1, 0],
    ]

    static let freezingRain: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 1, 0, 1, 0, 1, 0, 0],
        [1, 0, 1, 0, 1, 0, 1, 0],
    ]

    static let snow: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 0, 0, 0, 0, 0, 1, 0],
        [0, 1, 0, 0, 0, 1, 0, 0],
    ]

    static let heavySnow: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 1, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 1, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 0, 0, 1, 0, 0, 1, 0],
        [0, 1, 0, 0, 1, 0, 0, 1],
    ]

    static let thunderstorm: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 0, 0, 1, 1, 0, 0, 0],
    ]

    static let severeThunderstorm: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 1, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 0, 1, 1, 0, 0, 0],
        [0, 0, 1, 0, 0, 1, 0, 0],
    ]
}

/// Canvas-drawn pixel glyph for one weather condition — the 8-bit stand-in
/// for the SF Symbol that used to sit in the header.
struct WeatherGlyphView: View {
    let condition: WeatherCondition
    let isDay: Bool
    var tint: Color = Theme.textDim

    var body: some View {
        Canvas { context, size in
            let grid = WeatherPixelArt.grid(for: condition, isDay: isDay)
            let rows = grid.count
            let cols = grid[0].count
            let pixel = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let originX = (size.width - pixel * CGFloat(cols)) / 2
            let originY = (size.height - pixel * CGFloat(rows)) / 2

            for (rowIndex, row) in grid.enumerated() {
                for (colIndex, cell) in row.enumerated() where cell != 0 {
                    let rect = CGRect(
                        x: originX + CGFloat(colIndex) * pixel,
                        y: originY + CGFloat(rowIndex) * pixel,
                        width: pixel * 0.92,
                        height: pixel * 0.92
                    )
                    context.fill(Path(rect), with: .color(tint))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The weather strip, confined to the TOP of the expanded panel: micro
/// clock + city line, then one 8-bit glyph + temperature + condition +
/// high/low. Minimal by construction — no sky, no ambience, no full-panel
/// layers (those lived in NotchContainerView and were removed 19/08/2026).
struct WeatherHeaderView: View {
    let phase: WeatherStore.Phase

    var body: some View {
        Group {
            switch phase {
            case .fresh(let snapshot):
                VStack(spacing: 3) {
                    HStack {
                        TimelineView(.periodic(from: .now, by: 30)) { timeline in
                            Text(WeatherFormat.clock(timeline.date))
                                .font(Theme.numeral(9))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        // The resolved city is always visible — precision is
                        // checkable at a glance, never silently wrong. Capped
                        // so a long name can never squeeze the clock.
                        Text(snapshot.city)
                            .font(Theme.body(8, weight: .medium))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 220, alignment: .trailing)
                    }
                    HStack(spacing: 6) {
                        WeatherGlyphView(condition: snapshot.condition, isDay: snapshot.isDay)
                            .frame(width: 18, height: 18)
                        Text(WeatherFormat.temperature(snapshot.temperatureC))
                            .font(Theme.numeral(14))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text(snapshot.condition.label)
                            .font(Theme.body(9.5, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        if let highLow = WeatherFormat.highLow(
                            max: snapshot.temperatureMaxC,
                            min: snapshot.temperatureMinC
                        ) {
                            Text("· \(highLow)")
                                .font(Theme.body(9.5))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                }
            case .unavailable:
                // Local clock only — it needs no network.
                HStack {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        Text(WeatherFormat.clock(timeline.date))
                            .font(Theme.numeral(9))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                }
            }
        }
    }
}
