import SwiftUI

/// The ambience is TWO layers, mounted by NotchContainerView:
/// - `WeatherSkyView` sits BEHIND the content and above the black notch
///   cap, so the night veil, stars and moon mix into the cap itself.
/// - `WeatherForegroundOverlay` sits ABOVE everything (cards, mascots,
///   buttons) — rain and snow fall ON the UI, like the iOS lock screen.
///   It never intercepts hits.
///
/// Both only exist while the panel is expanded on page 0 (Now), so their
/// TimelineViews cost zero CPU anywhere else.

// MARK: - Sky (behind the content, over the notch cap)

struct WeatherSkyView: View {
    let phase: WeatherStore.Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch phase {
            case .fresh(let snapshot):
                switch snapshot.condition {
                case .rain, .storm:
                    rainWash
                case .snow:
                    snowWash
                case .cloudy:
                    cloudVeil
                case .partlyCloudy:
                    if snapshot.isDay {
                        ZStack {
                            cloudVeil.opacity(0.6)
                            sunGlow
                        }
                    } else {
                        ZStack(alignment: .topTrailing) {
                            nightVeil
                            StarField(density: 0.6)
                            moon
                        }
                    }
                case .clear:
                    if snapshot.isDay {
                        sunGlow
                    } else {
                        ZStack(alignment: .topTrailing) {
                            nightVeil
                            if reduceMotion {
                                StarDust(density: 1.0)
                            } else {
                                StarField(density: 1.0)
                            }
                            moon
                        }
                    }
                }
            case .unavailable:
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }

    /// Rain also tints the whole panel: the wet-glass wash lives in the
    /// sky layer so the cap gets it too.
    private var rainWash: some View {
        Color(red: 0.45, green: 0.6, blue: 0.9).opacity(0.07)
    }

    private var snowWash: some View {
        Color.white.opacity(0.06)
    }

    /// A grey overcast wash falling from the top — reads as "closed sky"
    /// against the dark panel without dimming the numbers.
    private var cloudVeil: some View {
        LinearGradient(
            colors: [
                Color(white: 0.62).opacity(0.24),
                Color(white: 0.62).opacity(0.08),
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Cool blue wash for clear nights — the panel reads as "night" before
    /// anything else.
    private var nightVeil: some View {
        LinearGradient(
            colors: [
                Color(red: 0.30, green: 0.45, blue: 0.85).opacity(0.14),
                Color(red: 0.20, green: 0.30, blue: 0.60).opacity(0.06),
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var sunGlow: some View {
        RadialGradient(
            colors: [
                Color.orange.opacity(0.16),
                Color.orange.opacity(0.05),
                .clear,
            ],
            center: .topTrailing,
            startRadius: 0,
            endRadius: 340
        )
    }

    /// A small bright moon with a wide soft halo, top-right.
    private var moon: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.75, green: 0.85, blue: 1.0).opacity(0.10))
                .frame(width: 110, height: 110)
                .blur(radius: 24)
            Circle()
                .fill(Color(red: 0.94, green: 0.96, blue: 1.0).opacity(0.85))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .fill(Color(red: 0.20, green: 0.26, blue: 0.45).opacity(0.45))
                        .frame(width: 9, height: 9)
                        .offset(x: -5, y: -4)
                )
        }
        .padding(.top, 10)
        .padding(.trailing, 14)
    }
}

// MARK: - Foreground (above the content)

/// Precipitation that falls ON the UI — cards, mascots, everything. Alpha
/// is scaled down versus the old background-only version so numbers stay
/// readable through the drops.
struct WeatherForegroundOverlay: View {
    let phase: WeatherStore.Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch phase {
            case .fresh(let snapshot):
                switch snapshot.condition {
                case .rain, .storm, .snow:
                    if reduceMotion {
                        Color.clear
                    } else {
                        ParticleField(
                            condition: snapshot.condition,
                            isDay: snapshot.isDay,
                            alphaScale: 0.55
                        )
                    }
                case .clear, .partlyCloudy, .cloudy:
                    Color.clear
                }
            case .unavailable:
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }
}

/// Canvas rain/storm/snow. Deterministic per-particle pseudo-randomness
/// (golden-ratio seed per index) — no RNG in the render loop, so the
/// animation stays stable across frame rates. Rain drops are rounded
/// strokes with real presence, not hairlines.
private struct ParticleField: View {
    let condition: WeatherCondition
    let isDay: Bool
    /// Multiplier for drop alpha — foreground drops sit on top of text and
    /// need to be quieter than background ones.
    let alphaScale: Double

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
                    let length = Self.length(for: condition, seed: seed)
                    let alpha = Self.alpha(for: condition, seed: seed) * alphaScale
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
                            with: .color(Color.white.opacity(0.06))
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

/// Twinkling stars for clear nights — the iOS lock-screen cue that made
/// "nothing" visible. Deterministic seeds; each star breathes on its own
/// phase so the sky feels alive, not strobing.
private struct StarField: View {
    let density: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(44 * density)
                for index in 0..<count {
                    let seed = Double(index) * 1.61803398875
                    let x = (seed * 311.0).truncatingRemainder(dividingBy: max(size.width, 1))
                    let y = (seed * 137.0).truncatingRemainder(dividingBy: max(size.height * 0.55, 1))
                    let twinkle = sin(t * 1.4 + seed * 47.0)
                    let alpha = 0.16 + 0.22 * max(0, twinkle)
                    let side = 1.0 + seed.truncatingRemainder(dividingBy: 1) * 1.5
                    let rect = CGRect(x: x, y: y, width: side, height: side)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
                }
            }
        }
    }
}

/// Static star dust for Reduce Motion nights: same sky, no twinkle loop.
private struct StarDust: View {
    let density: Double

    var body: some View {
        Canvas { context, size in
            let count = Int(44 * density)
            for index in 0..<count {
                let seed = Double(index) * 1.61803398875
                let x = (seed * 311.0).truncatingRemainder(dividingBy: max(size.width, 1))
                let y = (seed * 137.0).truncatingRemainder(dividingBy: max(size.height * 0.55, 1))
                let side = 1.0 + seed.truncatingRemainder(dividingBy: 1) * 1.5
                let rect = CGRect(x: x, y: y, width: side, height: side)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.24)))
            }
        }
    }
}
