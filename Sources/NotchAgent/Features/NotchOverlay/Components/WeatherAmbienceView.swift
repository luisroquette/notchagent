import SwiftUI

/// The ambience is TWO layers, mounted by NotchContainerView:
/// - `WeatherSkyView` sits BEHIND the content and above the black notch
///   cap, so the night veil, stars and moon mix into the cap itself.
/// - `WeatherForegroundOverlay` sits ABOVE everything (cards, mascots,
///   buttons) — rain and snow fall ON the UI, like the iOS lock screen.
///   It never intercepts hits.
///
/// Every condition is alive, the way it is in nature: stars twinkle,
/// rain falls, the sun breathes and its rays rotate, clouds drift, snow
/// floats down, the moon's halo pulses. All motion is deterministic
/// (golden-ratio seeds + time), stable across frame rates, and every
/// TimelineView dies with the layer — zero CPU anywhere else. Reduce
/// Motion swaps each animated piece for its static twin.

// MARK: - Sky (behind the content, over the notch cap)

struct WeatherSkyView: View {
    let phase: WeatherStore.Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch phase {
            case .fresh(let snapshot):
                switch snapshot.condition {
                case .rain, .drizzle, .heavyRain, .freezingRain,
                     .thunderstorm, .severeThunderstorm:
                    rainWash
                case .snow:
                    snowWash
                case .heavySnow:
                    snowWash.opacity(1.6)
                case .fog:
                    fogWash
                case .cloudy:
                    ZStack {
                        cloudVeil
                        if reduceMotion {
                            StaticClouds(density: 1.0)
                        } else {
                            CloudDrift(density: 1.0)
                        }
                    }
                case .partlyCloudy:
                    if snapshot.isDay {
                        ZStack {
                            cloudVeil.opacity(0.5)
                            if reduceMotion {
                                StaticClouds(density: 0.7)
                                sunGlow
                            } else {
                                CloudDrift(density: 0.7)
                                SunView().opacity(0.55)
                            }
                        }
                    } else {
                        ZStack(alignment: .topTrailing) {
                            nightVeil
                            StarField(density: 0.6)
                            MoonView(pulsing: !reduceMotion)
                        }
                    }
                case .clear:
                    if snapshot.isDay {
                        if reduceMotion {
                            sunGlow
                        } else {
                            SunView()
                        }
                    } else {
                        ZStack(alignment: .topTrailing) {
                            nightVeil
                            if reduceMotion {
                                StarDust(density: 1.0)
                            } else {
                                StarField(density: 1.0)
                            }
                            MoonView(pulsing: !reduceMotion)
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

    /// Fog washes the whole panel into a soft grey — no hard edges left.
    private var fogWash: some View {
        LinearGradient(
            colors: [
                Color(white: 0.68).opacity(0.20),
                Color(white: 0.60).opacity(0.12),
                Color(white: 0.55).opacity(0.06),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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

    /// Static Reduce-Motion sun: a warm glow, no motion.
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
}

// MARK: - Foreground (above the content)

/// Precipitation that falls ON the UI — cards, mascots, everything. Alpha
/// is scaled down versus the old background-only version so numbers stay
/// readable through the drops. Clear nights also get a front star dust so
/// the sky reads above the cards, not only between them.
struct WeatherForegroundOverlay: View {
    let phase: WeatherStore.Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch phase {
            case .fresh(let snapshot):
                switch snapshot.condition {
                case .rain, .drizzle, .heavyRain, .freezingRain, .snow,
                     .heavySnow, .thunderstorm, .severeThunderstorm:
                    if reduceMotion {
                        Color.clear
                    } else {
                        ParticleField(
                            condition: snapshot.condition,
                            isDay: snapshot.isDay,
                            windSpeedKmh: snapshot.windSpeedKmh,
                            alphaScale: 0.55
                        )
                    }
                case .clear:
                    if !snapshot.isDay {
                        if reduceMotion {
                            StarDust(density: 0.45, alphaScale: 0.7)
                        } else {
                            StarField(density: 0.45, alphaScale: 0.7)
                        }
                    } else {
                        Color.clear
                    }
                case .partlyCloudy:
                    if !snapshot.isDay {
                        if reduceMotion {
                            StarDust(density: 0.3, alphaScale: 0.6)
                        } else {
                            StarField(density: 0.3, alphaScale: 0.6)
                        }
                    } else {
                        Color.clear
                    }
                case .cloudy, .fog:
                    Color.clear
                }
            case .unavailable:
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Sun (day, clear / partly cloudy)

/// A living sun: the halo breathes, the core glows and eight rays rotate
/// at a lazy pace (one turn per ~1.5 min) — visible life without glare.
private struct SunView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let cx = size.width - 46
                let cy = 30.0

                // Breathing halo: concentric rings whose radius and alpha
                // pulse on staggered phases.
                let basePulse = 0.10 + 0.05 * sin(t * 0.7)
                for ring in 0..<5 {
                    let radius = 26.0 + Double(ring) * 22.0 + 5.0 * sin(t * 0.7 + Double(ring) * 0.8)
                    let alpha = basePulse * max(0, 0.5 - Double(ring) * 0.09)
                    let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.orange.opacity(alpha)))
                }

                // Core.
                let coreRect = CGRect(x: cx - 12, y: cy - 12, width: 24, height: 24)
                context.fill(Path(ellipseIn: coreRect), with: .color(Color.orange.opacity(0.30)))

                // Rotating rays, each with its own breathing length.
                for ray in 0..<8 {
                    let angle = Double(ray) * .pi / 4 + t * 0.07
                    let inner = 34.0
                    let outer = 58.0 + 6.0 * sin(t * 0.7 + Double(ray))
                    var path = Path()
                    path.move(to: CGPoint(x: cx + cos(angle) * inner, y: cy + sin(angle) * inner))
                    path.addLine(to: CGPoint(x: cx + cos(angle) * outer, y: cy + sin(angle) * outer))
                    context.stroke(
                        path,
                        with: .color(Color.orange.opacity(0.10)),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }
            }
        }
    }
}

// MARK: - Clouds (cloudy / partly cloudy)

/// Clouds drifting sideways at their own paces — the closed sky moves.
private struct CloudDrift: View {
    let density: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(5 * density)
                for index in 0..<count {
                    let seed = Double(index) * 1.61803398875
                    let cloudWidth = 120.0 + seed.truncatingRemainder(dividingBy: 1) * 80
                    let speed = 6.0 + seed.truncatingRemainder(dividingBy: 1) * 8
                    let span = size.width + cloudWidth * 2
                    let x = (seed * 400.0 + t * speed).truncatingRemainder(dividingBy: span) - cloudWidth
                    let y = 26.0 + seed.truncatingRemainder(dividingBy: 1) * 90
                    let alpha = 0.07 + seed.truncatingRemainder(dividingBy: 1) * 0.05
                    let color = Color(white: 0.75).opacity(alpha)

                    // A cloud = three overlapping soft lobes.
                    for lobe in 0..<3 {
                        let lx = x + Double(lobe) * cloudWidth * 0.35
                        let ly = y + (lobe == 1 ? -10 : 4)
                        let w = cloudWidth * (lobe == 1 ? 0.55 : 0.42)
                        let h = w * 0.45
                        context.fill(
                            Path(ellipseIn: CGRect(x: lx, y: ly, width: w, height: h)),
                            with: .color(color)
                        )
                    }
                }
            }
        }
    }
}

/// Static Reduce-Motion clouds: same sky, parked.
private struct StaticClouds: View {
    let density: Double

    var body: some View {
        Canvas { context, size in
            let count = Int(5 * density)
            for index in 0..<count {
                let seed = Double(index) * 1.61803398875
                let cloudWidth = 120.0 + seed.truncatingRemainder(dividingBy: 1) * 80
                let x = (seed * 400.0).truncatingRemainder(dividingBy: max(size.width + cloudWidth * 2, 1)) - cloudWidth
                let y = 26.0 + seed.truncatingRemainder(dividingBy: 1) * 90
                let alpha = 0.07 + seed.truncatingRemainder(dividingBy: 1) * 0.05
                let color = Color(white: 0.75).opacity(alpha)
                for lobe in 0..<3 {
                    let lx = x + Double(lobe) * cloudWidth * 0.35
                    let ly = y + (lobe == 1 ? -10 : 4)
                    let w = cloudWidth * (lobe == 1 ? 0.55 : 0.42)
                    let h = w * 0.45
                    context.fill(Path(ellipseIn: CGRect(x: lx, y: ly, width: w, height: h)), with: .color(color))
                }
            }
        }
    }
}

// MARK: - Moon (clear / partly cloudy nights)

/// Crescent moon parked in the empty cap strip, halo breathing slowly.
private struct MoonView: View {
    let pulsing: Bool

    var body: some View {
        Group {
            if pulsing {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let halo = 68.0 + 8.0 * sin(t * 0.5)
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.75, green: 0.85, blue: 1.0).opacity(0.10 + 0.03 * sin(t * 0.5)))
                            .frame(width: halo, height: halo)
                            .blur(radius: 16)
                        crescent
                    }
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.75, green: 0.85, blue: 1.0).opacity(0.12))
                        .frame(width: 68, height: 68)
                        .blur(radius: 16)
                    crescent
                }
            }
        }
        .padding(.top, 4)
        .padding(.trailing, 26)
    }

    private var crescent: some View {
        Circle()
            .fill(Color(red: 0.94, green: 0.96, blue: 1.0).opacity(0.9))
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .fill(Color(red: 0.20, green: 0.26, blue: 0.45).opacity(0.45))
                    .frame(width: 8, height: 8)
                    .offset(x: -4, y: -3)
            )
    }
}

// MARK: - Particles (rain / storm / snow)

/// Canvas rain/storm/snow. Deterministic per-particle pseudo-randomness
/// (golden-ratio seed per index) — no RNG in the render loop, so the
/// animation stays stable across frame rates. Rain drops are rounded
/// strokes with real presence, not hairlines.
private struct ParticleField: View {
    let condition: WeatherCondition
    let isDay: Bool
    /// Wind speed in km/h — leans the falling particles sideways.
    let windSpeedKmh: Double
    /// Multiplier for drop alpha — foreground drops sit on top of text and
    /// need to be quieter than background ones.
    let alphaScale: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = Self.count(for: condition)
                // Wind pushes particles sideways: ~1.2 px/s per km/h.
                let windDrift = windSpeedKmh * 1.2

                for index in 0..<count {
                    let seed = Double(index) * 1.61803398875
                    let speed = Self.speed(for: condition, seed: seed)
                    let baseX = (seed * 97.0).truncatingRemainder(dividingBy: max(size.width, 1))
                    let spanX = max(size.width + 80, 1)
                    let x = (baseX + t * windDrift).truncatingRemainder(dividingBy: spanX) - 40
                    let y = (seed * 173.0 + t * speed).truncatingRemainder(dividingBy: max(size.height + 40, 1)) - 20
                    let length = Self.length(for: condition, seed: seed)
                    let alpha = Self.alpha(for: condition, seed: seed) * alphaScale

                    switch Self.kind(for: condition, seed: seed) {
                    case .drop:
                        let color = Color(red: 0.70, green: 0.79, blue: 0.98).opacity(alpha)
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        // Lean with the wind plus a fixed slant.
                        let lean = length * 0.3 + windDrift * 0.35
                        path.addLine(to: CGPoint(x: x - lean, y: y + length))
                        context.stroke(
                            path,
                            with: .color(color),
                            style: StrokeStyle(lineWidth: Self.strokeWidth(for: condition, seed: seed), lineCap: .round)
                        )
                    case .flake:
                        let color = Color.white.opacity(alpha)
                        let side = Self.flakeSize(for: condition, seed: seed)
                        let rect = CGRect(x: x, y: y, width: side, height: side)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    case .pellet:
                        // Freezing rain's ice nodules: bright core, soft edge.
                        let color = Color(red: 0.92, green: 0.97, blue: 1.0).opacity(alpha)
                        let side = 2.4 + seed.truncatingRemainder(dividingBy: 1) * 1.4
                        let rect = CGRect(x: x, y: y, width: side, height: side)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }

                if condition == .thunderstorm || condition == .severeThunderstorm {
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

    private enum ParticleKind {
        case drop
        case flake
        case pellet
    }

    private static func kind(for condition: WeatherCondition, seed: Double) -> ParticleKind {
        switch condition {
        case .snow, .heavySnow: .flake
        case .freezingRain:
            // Chaotic mix: half fast rain lines, half bright ice nodules.
            seed.truncatingRemainder(dividingBy: 1) < 0.5 ? .drop : .pellet
        default: .drop
        }
    }

    private static func count(for condition: WeatherCondition) -> Int {
        switch condition {
        case .drizzle: 34
        case .heavyRain, .severeThunderstorm: 42
        case .heavySnow: 34
        case .thunderstorm: 36
        case .snow: 26
        default: 30
        }
    }

    private static func speed(for condition: WeatherCondition, seed: Double) -> Double {
        let base: Double
        switch condition {
        case .snow: base = 16
        case .heavySnow: base = 34
        case .drizzle: base = 55
        case .heavyRain, .severeThunderstorm: base = 150
        default: base = 90
        }
        return base + seed.truncatingRemainder(dividingBy: 1) * 40
    }

    private static func length(for condition: WeatherCondition, seed: Double) -> Double {
        let base: Double
        switch condition {
        case .snow, .heavySnow: base = 0
        case .drizzle: base = 6
        case .heavyRain, .severeThunderstorm: base = 20
        default: base = 14
        }
        let span: Double = condition == .drizzle ? 5 : 12
        return base + seed.truncatingRemainder(dividingBy: 1) * span
    }

    private static func strokeWidth(for condition: WeatherCondition, seed: Double) -> Double {
        let base: Double
        switch condition {
        case .drizzle: base = 0.8
        case .heavyRain, .severeThunderstorm: base = 2.2
        case .thunderstorm: base = 1.6
        default: base = 1.3
        }
        return base + seed.truncatingRemainder(dividingBy: 1) * 0.6
    }

    private static func flakeSize(for condition: WeatherCondition, seed: Double) -> Double {
        let base: Double = condition == .heavySnow ? 4.2 : 3.2
        return base + seed.truncatingRemainder(dividingBy: 1) * 1.6
    }

    private static func alpha(for condition: WeatherCondition, seed: Double) -> Double {
        let floor: Double
        switch condition {
        case .drizzle: floor = 0.14
        case .heavyRain, .severeThunderstorm: floor = 0.30
        case .heavySnow: floor = 0.30
        case .thunderstorm: floor = 0.26
        case .freezingRain: floor = 0.22
        default: floor = 0.22
        }
        return min(0.44, floor + seed.truncatingRemainder(dividingBy: 1) * 0.10)
    }
}

// MARK: - Stars (clear / partly cloudy nights)

/// Twinkling stars for clear nights — the iOS lock-screen cue that made
/// "nothing" visible. Deterministic seeds; each star breathes on its own
/// phase so the sky feels alive, not strobing.
private struct StarField: View {
    let density: Double
    /// Front stars sit on top of the cards and need to be quieter than
    /// background ones.
    var alphaScale: Double = 1.0

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
                    let alpha = (0.16 + 0.22 * max(0, twinkle)) * alphaScale
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
    var alphaScale: Double = 1.0

    var body: some View {
        Canvas { context, size in
            let count = Int(44 * density)
            for index in 0..<count {
                let seed = Double(index) * 1.61803398875
                let x = (seed * 311.0).truncatingRemainder(dividingBy: max(size.width, 1))
                let y = (seed * 137.0).truncatingRemainder(dividingBy: max(size.height * 0.55, 1))
                let side = 1.0 + seed.truncatingRemainder(dividingBy: 1) * 1.5
                let rect = CGRect(x: x, y: y, width: side, height: side)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.24 * alphaScale)))
            }
        }
    }
}
