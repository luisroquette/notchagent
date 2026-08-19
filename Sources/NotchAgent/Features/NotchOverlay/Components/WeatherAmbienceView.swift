import SwiftUI

/// The ambience is TWO layers, mounted by NotchContainerView:
/// - `WeatherSkyView` sits BEHIND the content and above the black notch
///   cap, so the procedural sky, stars and moon mix into the cap itself.
/// - `WeatherForegroundOverlay` sits ABOVE everything (cards, mascots,
///   buttons) — rain and snow fall ON the UI, like the iOS lock screen.
///   It never intercepts hits.
///
/// The sky is a procedural gradient: SolarPhase (dawn/day/dusk/night from
/// sunrise/sunset) drives SkyPalette (Rayleigh sunset, blue hour,
/// per-condition desaturation), recomputed every 30s so dusk cools in
/// real time. Everything else is alive too — stars twinkle, the sun
/// breathes with rotating rays, clouds drift, precipitation falls with
/// per-intensity physics, the moon shows its REAL phase. All motion is
/// deterministic (golden-ratio seeds + time), stable across frame rates,
/// and every TimelineView dies with the layer — zero CPU anywhere else.
/// Reduce Motion swaps each animated piece for its static twin.

// MARK: - Sky (behind the content, over the notch cap)

struct WeatherSkyView: View {
    let phase: WeatherStore.Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch phase {
            case .fresh(let snapshot):
                ZStack {
                    // The procedural sky: solar phase drives the palette,
                    // the condition drives its desaturation. Present enough
                    // to read as weather, never enough to hide the data.
                    SkyGradientView(snapshot: snapshot)
                        .opacity(0.65)

                    switch snapshot.condition {
                    case .clear:
                        if snapshot.isDay {
                            RealSunView(pulsing: !reduceMotion)
                        } else {
                            nightSky(snapshot, starDensity: 1.0)
                        }
                    case .partlyCloudy:
                        RealCloudBank(pulsing: !reduceMotion, windKmh: snapshot.windSpeedKmh)
                        if snapshot.isDay {
                            RealSunView(pulsing: !reduceMotion).opacity(0.6)
                        } else {
                            nightSky(snapshot, starDensity: 0.5)
                        }
                    case .cloudy:
                        RealCloudBank(pulsing: !reduceMotion, windKmh: snapshot.windSpeedKmh)
                    case .fog:
                        if reduceMotion { StaticFog() } else { FogDrift(density: 1.0) }
                    case .drizzle, .rain, .heavyRain, .freezingRain:
                        if reduceMotion { StaticClouds(density: 1.2) } else { CloudDrift(density: 1.2, windKmh: snapshot.windSpeedKmh) }
                    case .snow, .heavySnow:
                        ZStack {
                            // Blizzard: a dense white mist kills contrast,
                            // like real whiteout.
                            if snapshot.condition == .heavySnow {
                                Color.white.opacity(0.10)
                            }
                            if reduceMotion {
                                StaticClouds(density: 1.1)
                            } else {
                                CloudDrift(density: 1.1, windKmh: snapshot.windSpeedKmh)
                            }
                        }
                    case .thunderstorm, .severeThunderstorm:
                        StormClouds(pulsing: !reduceMotion)
                    }
                }
            case .unavailable:
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }

    /// Stars + the real-phase moon, shared by clear and partly-cloudy
    /// nights.
    @ViewBuilder
    private func nightSky(_ snapshot: WeatherSnapshot, starDensity: Double) -> some View {
        if reduceMotion {
            StarDust(density: starDensity)
        } else {
            StarField(density: starDensity)
        }
        MoonView(phase: MoonPhase.illumination(at: Date()), pulsing: !reduceMotion)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

/// The procedural gradient, recomputed every 30s: as the local clock
/// crosses the dawn/dusk windows, the palette slides from night to golden
/// fire to day — in real time, like Apple Weather.
private struct SkyGradientView: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let solar = SolarPhase.at(
                now: timeline.date,
                sunrise: snapshot.sunrise,
                sunset: snapshot.sunset,
                isDay: snapshot.isDay
            )
            let palette = SkyPalette.make(
                phase: solar.phase,
                transition: solar.transition,
                condition: snapshot.condition
            )
            LinearGradient(
                colors: [
                    Color(red: palette.top.r, green: palette.top.g, blue: palette.top.b),
                    Color(red: palette.bottom.r, green: palette.bottom.g, blue: palette.bottom.b),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// Static Reduce-Motion sun: a warm glow, no motion.
private struct StaticSunGlow: View {
    var body: some View {
        RadialGradient(
            colors: [
                Color.orange.opacity(0.16),
                Color.orange.opacity(0.05),
                .clear,
            ],
            center: .topTrailing,
            startRadius: 0,
            endRadius: 230
        )
    }
}

// MARK: - Generated art (gpt-image-2)

/// Realistic weather art generated with OpenAI image models, bundled under
/// Resources/Weather/ as alpha PNGs (gpt-image-1 transparent, or
/// gpt-image-2 black plate + chroma-key in gen-weather-assets.py). Plain
/// alpha compositing — no blend modes, so opacity and clipping stay
/// predictable.
enum WeatherArt {
    /// Bundled PNG; nil when the asset is missing (test bundles, first
    /// run before make-app.sh copies it) — callers fall back to the
    /// procedural views.
    static func image(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Weather") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

/// The generated sun: real atmospheric glow, breathing slowly, with a
/// gentle sway so the light feels alive. Anchored inside the panel bounds
/// — the glow fades into the black plate before the image edge, so the
/// panel never hard-cuts the drawing.
private struct RealSunView: View {
    let pulsing: Bool

    var body: some View {
        if let image = WeatherArt.image(named: "weather-sun") {
            Group {
                if pulsing {
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(1.0 + 0.015 * sin(t * 0.4))
                            .offset(y: 2.0 * sin(t * 0.3))
                    }
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .opacity(0.9)
            .frame(width: 300, height: 300)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 24)
            .padding(.trailing, 20)
        } else {
            if pulsing { SunView() } else { StaticSunGlow() }
        }
    }
}

/// The generated cloud bank: three depth layers drifting at different
/// speeds (wind pushes them faster), screen-blended over the sky.
private struct RealCloudBank: View {
    let pulsing: Bool
    let windKmh: Double

    var body: some View {
        if let image = WeatherArt.image(named: "weather-clouds") {
            Group {
                if pulsing {
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let wind = 1.0 + max(0, windKmh - 20) / 20 * 0.5
                        ZStack(alignment: .top) {
                            cloudSlice(image, t: t, speed: 1.4 * wind, width: 280, y: 8, opacity: 0.5)
                            cloudSlice(image, t: t, speed: 2.2 * wind, width: 340, y: 30, opacity: 0.55)
                            cloudSlice(image, t: t, speed: 3.6 * wind, width: 460, y: 60, opacity: 0.45)
                        }
                    }
                } else {
                    ZStack(alignment: .top) {
                        cloudSlice(image, t: 0, speed: 0, width: 340, y: 30, opacity: 0.55)
                        cloudSlice(image, t: 0, speed: 0, width: 460, y: 60, opacity: 0.45)
                    }
                }
            }
        } else {
            if pulsing { CloudDrift(density: 1.0, windKmh: windKmh) } else { StaticClouds(density: 1.0) }
        }
    }

    private func cloudSlice(
        _ image: NSImage,
        t: Double,
        speed: Double,
        width: CGFloat,
        y: CGFloat,
        opacity: Double
    ) -> some View {
        // Wraps horizontally: each layer re-enters from the left after
        // leaving on the right, like a real cloud bank.
        let span = 660.0 + Double(width)
        let x = (t * speed).truncatingRemainder(dividingBy: span) - Double(width)
        return Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .opacity(opacity)
            .offset(x: x, y: y)
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
                        windDust(snapshot)
                    }
                case .partlyCloudy:
                    if !snapshot.isDay {
                        if reduceMotion {
                            StarDust(density: 0.3, alphaScale: 0.6)
                        } else {
                            StarField(density: 0.3, alphaScale: 0.6)
                        }
                    } else {
                        windDust(snapshot)
                    }
                case .cloudy:
                    // Depth: a second cloud layer slides CLOSE to the
                    // viewer (faster, bigger, fainter) over the sky layer.
                    if snapshot.isDay {
                        if reduceMotion {
                            Color.clear
                        } else {
                            FrontCloudDrift(windKmh: snapshot.windSpeedKmh)
                        }
                    } else {
                        windDust(snapshot)
                    }
                case .fog:
                    // Fog masses dragged right in front of the viewer —
                    // "suspensão de gotículas no ar".
                    if reduceMotion {
                        Color.clear
                    } else {
                        FrontFogDrift()
                    }
                }
            case .unavailable:
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }

    /// Strong wind without precipitation: dust streaks racing across —
    /// the air itself becomes visible. Only above 25 km/h.
    @ViewBuilder
    private func windDust(_ snapshot: WeatherSnapshot) -> some View {
        if snapshot.windSpeedKmh > 25 {
            if reduceMotion {
                Color.clear
            } else {
                DustDrift(intensity: min(1.2, snapshot.windSpeedKmh / 40))
            }
        } else {
            Color.clear
        }
    }
}

/// The close cloud layer: bigger, faster, fainter than the sky clouds —
/// parallax sells the depth between the two planes.
private struct FrontCloudDrift: View {
    let windKmh: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<3 {
                    let seed = Double(index) * 1.61803398875
                    let cloudWidth = 240.0 + seed.truncatingRemainder(dividingBy: 1) * 140
                    let baseSpeed = 26.0 + seed.truncatingRemainder(dividingBy: 1) * 14
                    let speed = baseSpeed * (1 + max(0, windKmh - 20) / 20 * 0.5)
                    let span = size.width + cloudWidth * 2
                    let x = (seed * 700.0 + t * speed).truncatingRemainder(dividingBy: span) - cloudWidth
                    let y = 70.0 + seed.truncatingRemainder(dividingBy: 1) * (size.height * 0.4)
                    let alpha = 0.03 + seed.truncatingRemainder(dividingBy: 1) * 0.025
                    let color = Color(white: 0.8).opacity(alpha)
                    for lobe in 0..<3 {
                        let lx = x + Double(lobe) * cloudWidth * 0.35
                        let ly = y + (lobe == 1 ? -16 : 6)
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

/// Fog masses passing right in front of the viewer — the "well near the
/// foreground" layer from the Apple renderer.
private struct FrontFogDrift: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<3 {
                    let seed = Double(index) * 1.61803398875
                    let fogWidth = 320.0 + seed.truncatingRemainder(dividingBy: 1) * 180
                    let speed = 12.0 + seed.truncatingRemainder(dividingBy: 1) * 8
                    let span = size.width + fogWidth * 2
                    let x = (seed * 900.0 + t * speed).truncatingRemainder(dividingBy: span) - fogWidth
                    let y = 60.0 + seed.truncatingRemainder(dividingBy: 1) * (size.height - 80)
                    let alpha = 0.04 + seed.truncatingRemainder(dividingBy: 1) * 0.04
                    let rect = CGRect(x: x, y: y, width: fogWidth, height: 64)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color(white: 0.78).opacity(alpha))
                    )
                }
            }
        }
    }
}

/// Horizontal dust streaks for windy dry conditions — fast, thin, faint.
private struct DustDrift: View {
    let intensity: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(14 * intensity)
                for index in 0..<count {
                    let seed = Double(index) * 1.61803398875
                    let speed = 180.0 + seed.truncatingRemainder(dividingBy: 1) * 120
                    let span = size.width + 160
                    let x = (seed * 260.0 + t * speed).truncatingRemainder(dividingBy: span) - 80
                    let y = (seed * 331.0).truncatingRemainder(dividingBy: max(size.height, 1))
                    let length = 26.0 + seed.truncatingRemainder(dividingBy: 1) * 34
                    let alpha = (0.05 + seed.truncatingRemainder(dividingBy: 1) * 0.05) * intensity
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + length, y: y + 2))
                    context.stroke(
                        path,
                        with: .color(Color(red: 0.72, green: 0.68, blue: 0.60).opacity(alpha)),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                    )
                }
            }
        }
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
                // Anchored inside the panel bounds: the halo fades in the
                // sky instead of being hard-cut by the top/right edges.
                let cx = size.width - 88
                let cy = 84.0

                // Breathing halo: concentric rings whose radius and alpha
                // pulse on staggered phases.
                let basePulse = 0.10 + 0.05 * sin(t * 0.7)
                for ring in 0..<5 {
                    let radius = 26.0 + Double(ring) * 18.0 + 5.0 * sin(t * 0.7 + Double(ring) * 0.8)
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
                    let outer = 50.0 + 6.0 * sin(t * 0.7 + Double(ray))
                    var path = Path()
                    path.move(to: CGPoint(x: cx + cos(angle) * inner, y: cy + sin(angle) * inner))
                    path.addLine(to: CGPoint(x: cx + cos(angle) * outer, y: cy + sin(angle) * outer))
                    context.stroke(
                        path,
                        with: .color(Color.orange.opacity(0.10)),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }

                // Lens flare: tiny ghost rings receding along the light
                // axis, drifting gently — the camera-glass refraction the
                // Apple renderer adds over every bright sun.
                let flareSway = sin(t * 0.35) * 2.5
                for ring in 0..<4 {
                    let distance = 26.0 + Double(ring) * 26.0
                    let radius = 5.0 + Double(ring) * 2.2
                    let alpha = 0.11 - Double(ring) * 0.022
                    let rect = CGRect(
                        x: cx - distance - radius,
                        y: cy - radius + flareSway,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(Color(red: 1.0, green: 0.85, blue: 0.6).opacity(max(0.02, alpha))),
                        style: StrokeStyle(lineWidth: 0.8)
                    )
                }
            }
        }
    }
}

// MARK: - Clouds (cloudy / partly cloudy / precipitation)

/// Clouds drifting sideways at their own paces — the closed sky moves.
private struct CloudDrift: View {
    let density: Double
    var windKmh: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(5 * density)
                for index in 0..<count {
                    let seed = Double(index) * 1.61803398875
                    let cloudWidth = 120.0 + seed.truncatingRemainder(dividingBy: 1) * 80
                    // Wind pushes the sky: ~5% faster per km/h over 20.
                    let baseSpeed = 6.0 + seed.truncatingRemainder(dividingBy: 1) * 8
                    let speed = baseSpeed * (1 + max(0, windKmh - 20) / 20 * 0.5)
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

/// Heavy dark storm clouds for thunder — loaded blocks that get lit from
/// the inside when the lightning fires.
private struct StormClouds: View {
    let pulsing: Bool

    var body: some View {
        if pulsing {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    drawClouds(context: context, size: size, flash: flashAlpha(t: t))
                }
            }
        } else {
            Canvas { context, size in
                drawClouds(context: context, size: size, flash: 0)
            }
        }
    }

    /// Lightning cadence: brief double-flash every ~6s.
    private func flashAlpha(t: Double) -> Double {
        let cycle = t.truncatingRemainder(dividingBy: 6)
        if cycle < 0.12 { return 0.55 }
        if cycle > 0.18 && cycle < 0.24 { return 0.35 }
        return 0
    }

    private func drawClouds(context: GraphicsContext, size: CGSize, flash: Double) {
        let count = 4
        for index in 0..<count {
            let seed = Double(index) * 1.61803398875
            let cloudWidth = 150.0 + seed.truncatingRemainder(dividingBy: 1) * 90
            let x = (seed * 300.0).truncatingRemainder(dividingBy: max(size.width, 1)) - cloudWidth * 0.3
            let y = 16.0 + seed.truncatingRemainder(dividingBy: 1) * 60
            // Dark body, lit from inside by the flash.
            let base = Color(white: 0.10).opacity(0.55)
            let lit = Color(white: 0.85).opacity(flash)
            for lobe in 0..<3 {
                let lx = x + Double(lobe) * cloudWidth * 0.35
                let ly = y + (lobe == 1 ? -14 : 5)
                let w = cloudWidth * (lobe == 1 ? 0.55 : 0.42)
                let h = w * 0.45
                let rect = CGRect(x: lx, y: ly, width: w, height: h)
                context.fill(Path(ellipseIn: rect), with: .color(base))
                if flash > 0, lobe == 1 {
                    let inner = rect.insetBy(dx: w * 0.2, dy: h * 0.25)
                    context.fill(Path(ellipseIn: inner), with: .color(lit))
                }
            }
        }
    }
}

// MARK: - Fog

/// Soft fog masses dragged close to the foreground — suspension in air.
private struct FogDrift: View {
    let density: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = Int(4 * density)
                for index in 0..<count {
                    let seed = Double(index) * 1.61803398875
                    let fogWidth = 200.0 + seed.truncatingRemainder(dividingBy: 1) * 120
                    let speed = 4.0 + seed.truncatingRemainder(dividingBy: 1) * 5
                    let span = size.width + fogWidth * 2
                    let x = (seed * 500.0 + t * speed).truncatingRemainder(dividingBy: span) - fogWidth
                    let y = 40.0 + seed.truncatingRemainder(dividingBy: 1) * (size.height - 60)
                    let alpha = 0.05 + seed.truncatingRemainder(dividingBy: 1) * 0.05
                    let rect = CGRect(x: x, y: y, width: fogWidth, height: 46)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.72).opacity(alpha)))
                }
            }
        }
    }
}

/// Static Reduce-Motion fog: parked masses.
private struct StaticFog: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<4 {
                let seed = Double(index) * 1.61803398875
                let fogWidth = 200.0 + seed.truncatingRemainder(dividingBy: 1) * 120
                let x = (seed * 500.0).truncatingRemainder(dividingBy: max(size.width + fogWidth * 2, 1)) - fogWidth
                let y = 40.0 + seed.truncatingRemainder(dividingBy: 1) * (size.height - 60)
                let alpha = 0.05 + seed.truncatingRemainder(dividingBy: 1) * 0.05
                let rect = CGRect(x: x, y: y, width: fogWidth, height: 46)
                context.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.72).opacity(alpha)))
            }
        }
    }
}

// MARK: - Moon (clear / partly cloudy nights)

/// The moon as it REALLY is tonight: continuous illumination phase
/// (synodic age) rendered with the classic two-circle terminator, halo
/// breathing slowly.
private struct MoonView: View {
    let phase: Double
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
                        disc
                    }
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.75, green: 0.85, blue: 1.0).opacity(0.12))
                        .frame(width: 68, height: 68)
                        .blur(radius: 16)
                    disc
                }
            }
        }
        // Inside the panel bounds: the halo must fade in the sky, never
        // get hard-cut by the panel's top/right edges.
        .padding(.top, 40)
        .padding(.trailing, 40)
    }

    /// Full lit disc + a sky-colored circle offset by the phase: new moon
    /// hides everything, full moon hides nothing, quarters split the disc.
    private var disc: some View {
        let lit = (1 - cos(2 * .pi * phase)) / 2
        // Terminator offset: -18 (full, shadow left) … 0 (new, dark) …
        // +18 (full, shadow right) — sign flips across the half-way point.
        let offset = (0.5 - phase) * 2 * 18
        let sky = Color(red: 0.06, green: 0.09, blue: 0.22)
        return ZStack {
            // No opacity floor: a new moon must leave ONLY the halo — a
            // residual disc would read as a half-lit moon.
            Circle()
                .fill(Color(red: 0.94, green: 0.96, blue: 1.0).opacity(0.9 * lit))
                .frame(width: 18, height: 18)
            Circle()
                .fill(sky)
                .frame(width: 19, height: 19)
                .offset(x: offset)
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
    }
}

// MARK: - Particles (precipitation)

/// Canvas rain/storm/snow. Deterministic per-particle pseudo-randomness
/// (golden-ratio seed per index) — no RNG in the render loop, so the
/// animation stays stable across frame rates. Rain drops are rounded
/// strokes with real presence, not hairlines.
private struct ParticleField: View {
    let condition: WeatherCondition
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

                // Heavy rain splashes off the bottom edge: bright specks
                // bouncing up where the drops "hit the ground".
                if condition == .heavyRain || condition == .severeThunderstorm {
                    for index in 0..<10 {
                        let seed = Double(index) * 1.61803398875
                        let bx = (seed * 131.0).truncatingRemainder(dividingBy: max(size.width, 1))
                        let bounce = abs(sin(t * 3 + seed * 13.0))
                        let by = size.height - 6 - bounce * 8
                        let side = 1.6 + seed.truncatingRemainder(dividingBy: 1)
                        let rect = CGRect(x: bx, y: by, width: side, height: side)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(Color(red: 0.75, green: 0.83, blue: 0.98).opacity(0.16 * alphaScale * bounce))
                        )
                    }
                }

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
                    // Cadence matches StormClouds (6s) so the sky
                    // illumination, the full flash and the bolt always
                    // fire together — one storm, one clock.
                    let flashCycle = t.truncatingRemainder(dividingBy: 6)
                    if flashCycle < 0.25 {
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(Color.white.opacity(0.06))
                        )
                    }
                    // A jagged bolt: brief, deterministic, forked — drawn
                    // only for the first flash instant.
                    if flashCycle < 0.12 {
                        drawBolt(context: context, size: size)
                    }
                }
            }
        }
    }

    /// A forked lightning bolt, jagged between cloud top and panel bottom.
    private func drawBolt(context: GraphicsContext, size: CGSize) {
        let startX = size.width * 0.62
        var path = Path()
        path.move(to: CGPoint(x: startX, y: 0))
        var y = 0.0
        var x = startX
        var step = 0
        while y < size.height * 0.85 {
            y += 26 + Double(step % 3) * 8
            x += (step.isMultiple(of: 2) ? -1 : 1) * (18 + Double(step % 2) * 14)
            path.addLine(to: CGPoint(x: x, y: y))
            step += 1
        }
        context.stroke(
            path,
            with: .color(Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.85)),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
        )
        // Secondary fork.
        var fork = Path()
        fork.move(to: CGPoint(x: x - 10, y: y - 34))
        fork.addLine(to: CGPoint(x: x - 34, y: y - 12))
        context.stroke(
            fork,
            with: .color(Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.55)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
        )
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
