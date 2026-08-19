import AppKit
import SwiftUI

/// Design language: "retro hardware gauge" — coral accent, state-colored big
/// numerals, chunky segmented meters. Every token is a dynamic color that
/// resolves for dark AND light appearances; the appearance itself is driven
/// per-window by `ThemeMode` (auto follows the system).
///
/// Physical honesty rule: the compact bar hugs the black camera housing, so it
/// is ALWAYS rendered dark regardless of theme (forced via `.colorScheme(.dark)`).
enum Theme {
    // Chassis & surfaces
    /// Expanded panel background. Pure black melts into the notch in dark mode.
    static let panel = dynamic(dark: .black, light: NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1))
    static let surface = dynamic(
        dark: NSColor(red: 0.086, green: 0.086, blue: 0.105, alpha: 1),
        light: NSColor(red: 1, green: 1, blue: 1, alpha: 1)
    )
    static let surfaceRaised = dynamic(
        dark: NSColor(red: 0.125, green: 0.125, blue: 0.15, alpha: 1),
        light: NSColor(red: 0.89, green: 0.89, blue: 0.91, alpha: 1)
    )
    static let hairline = dynamic(dark: NSColor.white.withAlphaComponent(0.08), light: NSColor.black.withAlphaComponent(0.10))

    // Glass surfaces
    /// The see-through body of a liquid-glass block, brighter at the top rim
    /// (specular) and nearly clear at the base. The sky behind stays clearly
    /// visible through the wash.
    static let glassTintTop = dynamic(
        dark: NSColor.white.withAlphaComponent(0.09),
        light: NSColor.white.withAlphaComponent(0.20)
    )
    static let glassTintBottom = dynamic(
        dark: NSColor.white.withAlphaComponent(0.04),
        light: NSColor.white.withAlphaComponent(0.10)
    )

    // Brand accent (Claude coral / terracotta) — deeper in light for contrast.
    static let coral = dynamic(
        dark: NSColor(red: 0.855, green: 0.467, blue: 0.341, alpha: 1),
        light: NSColor(red: 0.76, green: 0.35, blue: 0.22, alpha: 1)
    )
    static let coralDim = dynamic(
        dark: NSColor(red: 0.855, green: 0.467, blue: 0.341, alpha: 0.55),
        light: NSColor(red: 0.76, green: 0.35, blue: 0.22, alpha: 0.55)
    )

    // State ramp — light variants darkened to hold AA contrast on white.
    static let ok = dynamic(
        dark: NSColor(red: 0.478, green: 0.773, blue: 0.498, alpha: 1),
        light: NSColor(red: 0.13, green: 0.52, blue: 0.24, alpha: 1)
    )
    static let caution = dynamic(
        dark: NSColor(red: 0.910, green: 0.765, blue: 0.353, alpha: 1),
        light: NSColor(red: 0.67, green: 0.50, blue: 0.03, alpha: 1)
    )
    static let warning = dynamic(
        dark: NSColor(red: 0.937, green: 0.663, blue: 0.306, alpha: 1),
        light: NSColor(red: 0.78, green: 0.44, blue: 0.05, alpha: 1)
    )
    static let danger = dynamic(
        dark: NSColor(red: 0.898, green: 0.282, blue: 0.302, alpha: 1),
        light: NSColor(red: 0.76, green: 0.13, blue: 0.16, alpha: 1)
    )

    // Text
    static let textPrimary = dynamic(dark: NSColor.white.withAlphaComponent(0.93), light: NSColor.black.withAlphaComponent(0.88))
    static let textSecondary = dynamic(dark: NSColor.white.withAlphaComponent(0.62), light: NSColor.black.withAlphaComponent(0.62))
    static let textDim = dynamic(dark: NSColor.white.withAlphaComponent(0.42), light: NSColor.black.withAlphaComponent(0.45))
    static let textFaint = dynamic(dark: NSColor.white.withAlphaComponent(0.26), light: NSColor.black.withAlphaComponent(0.30))

    // Chart & meter furniture
    static let marker = dynamic(dark: .white, light: NSColor.black.withAlphaComponent(0.85))
    static let socket = dynamic(dark: NSColor.white.withAlphaComponent(0.10), light: NSColor.black.withAlphaComponent(0.10))
    static let gridline = dynamic(dark: NSColor.white.withAlphaComponent(0.06), light: NSColor.black.withAlphaComponent(0.08))
    static let gridStrong = dynamic(dark: NSColor.white.withAlphaComponent(0.18), light: NSColor.black.withAlphaComponent(0.22))
    static let bubble = dynamic(dark: NSColor.black.withAlphaComponent(0.85), light: NSColor.white.withAlphaComponent(0.95))

    // Re-picked 2026-08-16 after a live user report ("can't tell the
    // lines apart") turned out to be measurable: the original 4 colors
    // validated at worst-pair ΔE 12 (dataviz skill's contrast checker),
    // below the 15 floor for normal color vision. These 4 clear that
    // floor against EACH OTHER (worst pair ΔE 16 dark / 19.7 dark
    // normal-vision — `node scripts/validate_palette.js
    // "#3987E5,#199E70,#9085E9,#D55181" --mode dark`, from the dataviz
    // skill directory).
    //
    // They do NOT all clear it against Theme.coral, which is always on
    // screen too (the dominant model's own hue is never drawn — coral
    // replaces it, so up to 3 of these 4 plus coral render together at
    // once). Checking every combination that can actually co-occur
    // (`--pairs all` on whichever 4 of the 5 are visible for a given
    // dominant model) finds real sub-floor pairs: coral↔Fable ΔE 11.7
    // normal-vision, Opus↔Haiku ΔE 9.8 normal-vision / down to 1.6-1.9
    // for deutan color blindness. The dataviz skill's rule is that
    // direct labels do NOT excuse a normal-vision-floor failure below
    // 15 — this is a deliberate, disclosed exception to that rule, not
    // an oversight: every line's identity is a permanently-visible text
    // label glued to the line's own end (see drawEndLabel /
    // "NOW · <model>" below), not a separate legend requiring
    // color-matching at a distance or a hover-only tooltip, which
    // meaningfully reduces how much the reader actually depends on hue
    // alone in practice. Re-stepping to a 5-color set that clears the
    // floor in every simultaneous combination was evaluated and rejected
    // — it isn't achievable within a reasonably distinct hue budget (see
    // the dataviz skill's own reference palette, which caps clean
    // all-pairs validation at 3 simultaneous categorical slots).
    static let modelHaiku = dynamic(
        dark: NSColor(red: 0.224, green: 0.529, blue: 0.898, alpha: 1),
        light: NSColor(red: 0.165, green: 0.471, blue: 0.839, alpha: 1)
    )
    static let modelSonnet = dynamic(
        dark: NSColor(red: 0.098, green: 0.620, blue: 0.439, alpha: 1),
        light: NSColor(red: 0.106, green: 0.686, blue: 0.478, alpha: 1)
    )
    static let modelOpus = dynamic(
        dark: NSColor(red: 0.565, green: 0.522, blue: 0.914, alpha: 1),
        light: NSColor(red: 0.290, green: 0.227, blue: 0.655, alpha: 1)
    )
    static let modelFable = dynamic(
        dark: NSColor(red: 0.835, green: 0.318, blue: 0.506, alpha: 1),
        light: NSColor(red: 0.910, green: 0.482, blue: 0.643, alpha: 1)
    )

    /// Fixed color identity for one of the 4 known Claude tiers — same
    /// substring match ModelProjection.shortName uses, so a model always
    /// reads as the same color whether or not it's the highlighted one.
    static func color(forModel model: String) -> Color {
        if model.contains("haiku") { return modelHaiku }
        if model.contains("sonnet") { return modelSonnet }
        if model.contains("opus") { return modelOpus }
        if model.contains("fable") { return modelFable }
        return textDim
    }

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Stick-style color ramp for utilization percentages, aligned with the
    /// user's alert thresholds for the top two bands.
    static func ramp(_ percent: Double, warningAt: Double = 70, criticalAt: Double = 90) -> Color {
        switch percent {
        case criticalAt...: danger
        case warningAt...: warning
        case 50...: caution
        default: ok
        }
    }

    /// State coherence rule: when the burn projection says the window will
    /// empty before its reset, no gauge may look calmer than `warning` —
    /// a green hero above an orange "runs out at…" verdict is a lie.
    static func riskTint(
        used: Double,
        projectedToRunOut: Bool,
        warningAt: Double = 70,
        criticalAt: Double = 90
    ) -> Color {
        let base = ramp(used, warningAt: warningAt, criticalAt: criticalAt)
        guard projectedToRunOut, base != danger else { return base }
        return warning
    }

    // Typography (native, tuned for the gauge look)
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension ThemeMode {
    /// nil = inherit the system appearance (Auto).
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }

    /// nil = follow the system (for SwiftUI-managed scenes like MenuBarExtra).
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .dark: .dark
        case .light: .light
        }
    }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}

/// Caps-mono micro label ("5 HOURS", "RESETS IN").
struct GaugeLabel: View {
    let text: String
    var color: Color = Theme.textDim
    var size: CGFloat = 8.5

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(size))
            .kerning(1.1)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Rounded status pill ("OK", "LIMITED", "BLOCKED").
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(8))
            .kerning(0.6)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
            .foregroundStyle(color)
    }
}

/// Liquid-glass surface ("Apple Liquid Glass" stand-in): a translucent
/// vertical gradient lets whatever is drawn BEHIND the block — the weather
/// sky, the panel fill — show through, standing in for refraction; a 1px
/// gradient stroke is the glass edge, and two layered soft shadows lift the
/// block off the background. Pure decoration. No NSVisualEffectView
/// Material: in this transparent panel it renders as a milky near-opaque
/// white, hiding the sky instead of frosting it. The specular rim lives
/// INSIDE the background gradient — an overlay would sit above the content
/// and wash out glyphs like the OpenAI knot.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.glassTintTop, Theme.glassTintBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.55), location: 0),
                                .init(color: .white.opacity(0.10), location: 0.55),
                                .init(color: .black.opacity(0.15), location: 1),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.16), radius: 9, y: 4)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

extension View {
    /// Applies the liquid-glass surface — see `GlassCard`.
    func glassCard(cornerRadius: CGFloat) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
