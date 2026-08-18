import Foundation

/// Procedural sky gradient — the Apple Weather look in pure math: a table
/// of RGBA vectors interpolated by solar phase, with the golden dawn fire
/// and the Rayleigh orange/pink sunset injected as sine-shaped pulses, and
/// a desaturation pass for overcast conditions. No images, no videos.
public struct SkyPalette: Equatable, Sendable {
    public struct RGB: Equatable, Sendable {
        public var r: Double
        public var g: Double
        public var b: Double

        public init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    public let top: RGB
    public let bottom: RGB

    public init(top: RGB, bottom: RGB) {
        self.top = top
        self.bottom = bottom
    }

    // MARK: Anchor colors

    /// Midday: vibrant sky blue top, softening toward the horizon.
    static let dayTop = RGB(0.23, 0.50, 0.95)
    static let dayBottom = RGB(0.55, 0.76, 1.00)
    /// Night: deep black-blue, faint navy at the bottom.
    static let nightTop = RGB(0.02, 0.04, 0.12)
    static let nightBottom = RGB(0.06, 0.09, 0.22)
    /// Blue hour (late dusk): navy into soft violet at the horizon.
    static let blueHourBottom = RGB(0.30, 0.22, 0.52)

    // MARK: The engine

    /// Interpolates the full sky for the current solar phase, then applies
    /// the weather's desaturation (fog washes almost everything out; a
    /// clear sky stays vivid).
    public static func make(
        phase: DayPhase,
        transition: Double,
        condition: WeatherCondition
    ) -> SkyPalette {
        let t = min(1, max(0, transition))

        let top: RGB
        let bottom: RGB
        switch phase {
        case .night:
            top = nightTop
            bottom = nightBottom

        case .day:
            top = dayTop
            bottom = dayBottom

        case .dawn:
            // Night → day, with a golden fire on the horizon that peaks
            // mid-transition (sunrise scattering) and fades into morning.
            top = lerp(nightTop, dayTop, t)
            let base = lerp(nightBottom, dayBottom, t)
            let fire = sin(.pi * t) * 0.55
            bottom = RGB(
                base.r + fire * 0.55,
                base.g + fire * 0.30,
                base.b + fire * 0.00
            )

        case .dusk:
            // Day → night. First half: Rayleigh orange/pink sunset that
            // peaks at the moment the sun crosses the horizon (t = 0.5).
            // Second half: blue hour, cooling into night.
            top = lerp(dayTop, nightTop, t)
            if t <= 0.5 {
                // The exact crossing moment (t = 0.5) is the fire's peak.
                // The base lingers warm (the sun is still low), then the
                // fire adds the Rayleigh orange/pink on top of it.
                let base = lerp(dayBottom, blueHourBottom, min(1, t * 1.6))
                let fire = sin(.pi * t) * 0.62
                bottom = RGB(
                    base.r + fire * 0.72,
                    base.g + fire * 0.25,
                    base.b + fire * 0.03
                )
            } else {
                bottom = lerp(blueHourBottom, nightBottom, (t - 0.5) * 2)
            }
        }

        return desaturate(
            SkyPalette(top: top, bottom: bottom),
            saturation: Self.saturation(for: condition)
        )
    }

    /// How much color survives the weather: clear keeps everything, fog
    /// kills almost all of it, overcast/precip sit in between.
    static func saturation(for condition: WeatherCondition) -> Double {
        switch condition {
        case .clear, .partlyCloudy: 1.0
        case .cloudy: 0.45
        case .fog: 0.15
        case .drizzle: 0.55
        case .rain, .snow: 0.5
        case .heavyRain, .heavySnow, .freezingRain: 0.4
        case .thunderstorm, .severeThunderstorm: 0.3
        }
    }

    /// Blends each color toward its own luminance (grey) — exactly the
    /// "desaturation layer" Apple applies to a cloudy sunset.
    static func desaturate(_ palette: SkyPalette, saturation: Double) -> SkyPalette {
        guard saturation < 1 else { return palette }
        let factor = 1 - saturation
        return SkyPalette(
            top: mix(palette.top, towardGrey: factor),
            bottom: mix(palette.bottom, towardGrey: factor)
        )
    }

    // MARK: Math

    static func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    static func mix(_ color: RGB, towardGrey factor: Double) -> RGB {
        let luma = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b
        return lerp(color, RGB(luma, luma, luma), factor)
    }
}
