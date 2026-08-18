import SwiftUI

/// The ambient background of the Now page. Subtlety is the contract:
/// nothing here exceeds alpha 0.16, and the whole view only exists while
/// the Now page is mounted (the pager unmounts it on every other page),
/// so the TimelineView costs zero CPU anywhere else.
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
                    LinearGradient(
                        colors: [Theme.surfaceRaised.opacity(0.6), Theme.surface],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(0.5)
                case .partlyCloudy:
                    sunGlow(isDay: snapshot.isDay).opacity(0.5)
                case .clear:
                    sunGlow(isDay: snapshot.isDay)
                }
            case .unavailable:
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }

    /// No-motion fallback: a barely-there tint instead of particles.
    @ViewBuilder
    private func staticVeil(_ snapshot: WeatherSnapshot) -> some View {
        Color.white.opacity(snapshot.condition == .snow ? 0.04 : 0.05)
    }

    @ViewBuilder
    private func sunGlow(isDay: Bool) -> some View {
        RadialGradient(
            colors: [
                (isDay ? Color.orange : Color.blue).opacity(0.05),
                .clear,
            ],
            center: .topTrailing,
            startRadius: 0,
            endRadius: 260
        )
    }
}

/// Canvas rain/storm/snow. Deterministic per-particle pseudo-randomness
/// (golden-ratio seed per index) — no RNG in the render loop, so the
/// animation stays stable across frame rates.
private struct ParticleField: View {
    let condition: WeatherCondition
    let isDay: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = Self.count(for: condition)
                for index in 0..<count {
                    let seed = Double(index) * 1.61803398875
                    let speed = Self.speed(for: condition, seed: seed)
                    let x = (seed * 97.0).truncatingRemainder(dividingBy: max(size.width, 1))
                    let y = (seed * 173.0 + t * speed).truncatingRemainder(dividingBy: max(size.height + 40, 1)) - 20
                    let length = 8.0 + (seed.truncatingRemainder(dividingBy: 1) * 10)
                    let alpha = Self.alpha(for: condition, seed: seed)
                    let color: Color = condition == .snow
                        ? Color.white.opacity(alpha)
                        : Color(red: 0.65, green: 0.75, blue: 0.95).opacity(alpha)

                    if condition == .rain || condition == .storm {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x - length * 0.3, y: y + length))
                        context.stroke(path, with: .color(color), lineWidth: 0.8)
                    } else {
                        let rect = CGRect(x: x, y: y, width: 2.2, height: 2.2)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                if condition == .storm {
                    let flashCycle = t.truncatingRemainder(dividingBy: 7)
                    if flashCycle < 0.25 {
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(Color.white.opacity(0.06))
                        )
                    }
                }
            }
        }
    }

    private static func count(for condition: WeatherCondition) -> Int {
        switch condition {
        case .storm: 30
        case .snow: 22
        default: 24
        }
    }

    private static func speed(for condition: WeatherCondition, seed: Double) -> Double {
        let base: Double = condition == .snow ? 14 : 60
        return base + seed.truncatingRemainder(dividingBy: 1) * 30
    }

    private static func alpha(for condition: WeatherCondition, seed: Double) -> Double {
        let floor: Double = condition == .storm ? 0.12 : 0.10
        return min(0.16, floor + seed.truncatingRemainder(dividingBy: 1) * 0.04)
    }
}
