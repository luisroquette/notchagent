import SwiftUI

/// The ambient background of the Now page. Presence is the contract:
/// the effect must read at a glance (like the iOS lock-screen weather),
/// without ever competing with the cards on top — particles stay under
/// alpha 0.4 and the whole view only exists while the Now page is mounted
/// (the pager unmounts it on every other page), so the TimelineView costs
/// zero CPU anywhere else.
struct WeatherAmbienceView: View {
    let phase: WeatherStore.Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch phase {
            case .fresh(let snapshot):
                switch snapshot.condition {
                case .rain, .storm, .snow:
                    if reduceMotion {
                        staticVeil(snapshot)
                    } else {
                        ParticleField(condition: snapshot.condition, isDay: snapshot.isDay)
                    }
                case .cloudy:
                    cloudVeil
                case .partlyCloudy:
                    ZStack {
                        cloudVeil.opacity(0.6)
                        sunGlow(isDay: snapshot.isDay).opacity(0.7)
                    }
                case .clear:
                    sunGlow(isDay: snapshot.isDay)
                }
            case .unavailable:
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }

    /// No-motion fallback: a visible tint instead of particles.
    @ViewBuilder
    private func staticVeil(_ snapshot: WeatherSnapshot) -> some View {
        switch snapshot.condition {
        case .snow:
            Color.white.opacity(0.07)
        default:
            Color(red: 0.62, green: 0.72, blue: 0.95).opacity(0.08)
        }
    }

    /// A grey overcast wash falling from the top — reads as "closed sky"
    /// against the dark panel without dimming the numbers.
    private var cloudVeil: some View {
        LinearGradient(
            colors: [
                Color(white: 0.62).opacity(0.17),
                Color(white: 0.62).opacity(0.05),
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func sunGlow(isDay: Bool) -> some View {
        ZStack {
            // Night reads as a cool veil over the whole panel.
            if !isDay {
                Color(red: 0.35, green: 0.5, blue: 0.9).opacity(0.06)
            }
            RadialGradient(
                colors: [
                    (isDay ? Color.orange : Color(red: 0.55, green: 0.7, blue: 1.0)).opacity(isDay ? 0.12 : 0.10),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 340
            )
        }
    }
}

/// Canvas rain/storm/snow. Deterministic per-particle pseudo-randomness
/// (golden-ratio seed per index) — no RNG in the render loop, so the
/// animation stays stable across frame rates. Rain drops are rounded
/// strokes with real presence (alpha 0.22-0.38), not hairlines.
private struct ParticleField: View {
    let condition: WeatherCondition
    let isDay: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate

                // Wet-glass wash under the drops: a faint cool tint that
                // makes the whole panel read as "rain", not just streaks.
                if condition == .rain || condition == .storm {
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(Color(red: 0.45, green: 0.6, blue: 0.9).opacity(0.06))
                    )
                }

                let count = Self.count(for: condition)
                for index in 0..<count {
                    let seed = Double(index) * 1.61803398875
                    let speed = Self.speed(for: condition, seed: seed)
                    let x = (seed * 97.0).truncatingRemainder(dividingBy: max(size.width, 1))
                    let y = (seed * 173.0 + t * speed).truncatingRemainder(dividingBy: max(size.height + 40, 1)) - 20
                    let length = Self.length(for: condition, seed: seed)
                    let alpha = Self.alpha(for: condition, seed: seed)
                    let color: Color = condition == .snow
                        ? Color.white.opacity(alpha)
                        : Color(red: 0.70, green: 0.79, blue: 0.98).opacity(alpha)

                    if condition == .rain || condition == .storm {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x - length * 0.3, y: y + length))
                        context.stroke(
                            path,
                            with: .color(color),
                            style: StrokeStyle(lineWidth: Self.strokeWidth(for: condition, seed: seed), lineCap: .round)
                        )
                    } else {
                        let side = 3.2 + seed.truncatingRemainder(dividingBy: 1) * 1.6
                        let rect = CGRect(x: x, y: y, width: side, height: side)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                if condition == .storm {
                    let flashCycle = t.truncatingRemainder(dividingBy: 5)
                    if flashCycle < 0.25 {
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(Color.white.opacity(0.09))
                        )
                    }
                }
            }
        }
    }

    private static func count(for condition: WeatherCondition) -> Int {
        switch condition {
        case .storm: 36
        case .snow: 26
        default: 30
        }
    }

    private static func speed(for condition: WeatherCondition, seed: Double) -> Double {
        let base: Double = condition == .snow ? 16 : 90
        return base + seed.truncatingRemainder(dividingBy: 1) * 40
    }

    private static func length(for condition: WeatherCondition, seed: Double) -> Double {
        let base: Double = condition == .snow ? 0 : 14
        return base + seed.truncatingRemainder(dividingBy: 1) * 12
    }

    private static func strokeWidth(for condition: WeatherCondition, seed: Double) -> Double {
        let base: Double = condition == .storm ? 1.6 : 1.3
        return base + seed.truncatingRemainder(dividingBy: 1) * 0.6
    }

    private static func alpha(for condition: WeatherCondition, seed: Double) -> Double {
        let floor: Double = condition == .storm ? 0.26 : 0.22
        return min(0.38, floor + seed.truncatingRemainder(dividingBy: 1) * 0.10)
    }
}
