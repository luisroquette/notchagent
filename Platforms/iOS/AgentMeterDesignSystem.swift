import AgentMeterCore
import SwiftUI
import UIKit

enum AgentMeterTheme {
    /// Tokens imported from Stitch's "Cinematic Engineering" system.
    static let spaceBlack = Color.black
    static let structuralBlack = Color(red: 0.075, green: 0.075, blue: 0.078) // #131314
    static let spectral = Color(red: 0.941, green: 0.941, blue: 0.980)
    static let signal = spectral
    static let nominal = spectral
    static let ice = spectral
    static let deepOcean = structuralBlack
    static let midnight = structuralBlack
    static let deck = Color(red: 0.055, green: 0.055, blue: 0.059) // #0E0E0F
    static let warning = Color(red: 0.929, green: 0.882, blue: 0.816) // #EDE1D0
    static let critical = Color(red: 1.0, green: 0.706, blue: 0.671) // #FFB4AB

    static let background = structuralBlack
    static let surface = Color.clear
    static let elevatedSurface = spectral.opacity(0.10)
    static let hull = deck
    static let hullSecondary = Color(red: 0.11, green: 0.106, blue: 0.11) // #1C1B1C
    static let mutedInk = Color(red: 0.78, green: 0.776, blue: 0.796) // #C7C6CB
    static let border = spectral.opacity(0.35)
    static let muted = mutedInk

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let control: CGFloat = 32
        static let panel: CGFloat = 0
    }

    static func providerColor(_ provider: AgentMeterProvider) -> Color {
        spectral
    }
}

enum AgentMeterTypography {
    static func regular(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom("D-DIN", size: size, relativeTo: style)
    }

    static func bold(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .headline
    ) -> Font {
        .custom("D-DIN-Bold", size: size, relativeTo: style)
    }

    static func telemetry(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom("RobotoMono-Regular", size: size, relativeTo: style)
    }

    static func fixedRegular(_ size: CGFloat) -> Font {
        .custom("D-DIN", fixedSize: size)
    }

    static func fixedBold(_ size: CGFloat) -> Font {
        .custom("D-DIN-Bold", fixedSize: size)
    }

    static func fixedTelemetry(_ size: CGFloat) -> Font {
        .custom("RobotoMono-Regular", fixedSize: size)
    }
}

struct AgentMeterPanel: ViewModifier {
    var padding: CGFloat = AgentMeterTheme.Space.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
    }
}

extension View {
    func agentMeterPanel(padding: CGFloat = AgentMeterTheme.Space.md) -> some View {
        modifier(AgentMeterPanel(padding: padding))
    }

}

struct AgentMeterBrandMark: View {
    var compact = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                Circle()
                    .stroke(AgentMeterTheme.border, lineWidth: 1)
                Circle()
                    .trim(from: 0.58, to: 0.88)
                    .stroke(AgentMeterTheme.signal, style: StrokeStyle(lineWidth: 2, lineCap: .square))
                    .rotationEffect(.degrees(-28))
            }
            .frame(width: compact ? 22 : 27, height: compact ? 22 : 27)

            Text("AGENTMETER")
                .font(AgentMeterTypography.fixedBold(compact ? 17 : 22))
                .tracking(compact ? 1.0 : 1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AgentMeter")
    }
}

struct AgentMeterSectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentMeterTheme.Space.sm) {
            Text(title)
                .font(AgentMeterTypography.fixedBold(12))
                .textCase(.uppercase)
                .tracking(1.15)
                .foregroundStyle(AgentMeterTheme.mutedInk)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AgentMeterTypography.fixedBold(15))
                    .foregroundStyle(AgentMeterTheme.signal)
                    .frame(minHeight: 44)
            }
        }
    }
}

struct AgentMeterStatusChip: View {
    let title: String
    var color = AgentMeterTheme.nominal
    var symbol = "checkmark"

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
            .font(AgentMeterTypography.fixedBold(12))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(color.opacity(0.10), in: Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.45), lineWidth: 0.75)
            }
    }
}

struct AgentMeterPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AgentMeterTypography.fixedBold(13))
            .textCase(.uppercase)
            .tracking(1.17)
            .foregroundStyle(configuration.isPressed ? Color.black : Color(red: 0.941, green: 0.941, blue: 0.980))
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, AgentMeterTheme.Space.md)
            .background(
                configuration.isPressed ? AgentMeterTheme.spectral : AgentMeterTheme.spectral.opacity(0.10),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(isEnabled ? AgentMeterTheme.border : AgentMeterTheme.border.opacity(0.35), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct AgentMeterSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AgentMeterTypography.fixedBold(13))
            .textCase(.uppercase)
            .tracking(1.17)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, AgentMeterTheme.Space.md)
            .background(AgentMeterTheme.spectral.opacity(0.10), in: Capsule())
            .overlay {
                Capsule().stroke(AgentMeterTheme.border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct AgentMeterProviderBadge: View {
    let provider: AgentMeterProvider
    var active = true
    var size: CGFloat = 42

    var body: some View {
        Text(code)
            .font(AgentMeterTypography.fixedBold(max(10, size * 0.28)))
            .tracking(-0.2)
            .foregroundStyle(active ? AgentMeterTheme.providerColor(provider) : AgentMeterTheme.mutedInk)
            .frame(width: size, height: size)
            .background(active ? AgentMeterTheme.providerColor(provider).opacity(0.10) : AgentMeterTheme.elevatedSurface)
            .overlay {
                Rectangle()
                    .stroke(active ? AgentMeterTheme.providerColor(provider).opacity(0.62) : AgentMeterTheme.border, lineWidth: 0.75)
            }
        .accessibilityHidden(true)
    }

    private var code: String {
        switch provider {
        case .claude: "CL"
        case .chatGPT: "AI"
        case .gemini: "GM"
        }
    }
}

struct AgentMeterOrbitMark: View {
    var progress: Double = 0.32

    var body: some View {
        ZStack {
            Circle().stroke(AgentMeterTheme.border, lineWidth: 1)
            Circle()
                .trim(from: 0, to: max(0.04, min(progress, 1)))
                .stroke(AgentMeterTheme.signal, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(AgentMeterTheme.signal)
                .frame(width: 7, height: 7)
                .offset(y: -34)
        }
        .frame(width: 76, height: 76)
        .accessibilityHidden(true)
    }
}

/// Ecosystem signature shared with AgentMeter: Desktop Bar: a tiny procedural
/// 8-bit companion. It carries status, never decorative or asset-backed.
struct AgentMeterPixelCompanion: View {
    var tint = AgentMeterTheme.nominal
    var distress: Double = 0

    private static let grid: [[Int]] = [
        [0, 1, 1, 0, 0, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 2, 2, 1, 1, 2, 2, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [0, 1, 0, 1, 1, 0, 1, 0],
    ]

    var body: some View {
        Canvas { context, size in
            let rows = Self.grid.count
            let columns = Self.grid[0].count
            let pixel = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
            let originX = (size.width - pixel * CGFloat(columns)) / 2
            let originY = (size.height - pixel * CGFloat(rows)) / 2
            let bodyColor = tint.opacity(1 - min(max(distress, 0), 1) * 0.35)

            for (rowIndex, row) in Self.grid.enumerated() {
                for (columnIndex, cell) in row.enumerated() where cell != 0 {
                    if distress > 0.6, rowIndex == 0, cell == 1 { continue }
                    let rect = CGRect(
                        x: originX + CGFloat(columnIndex) * pixel,
                        y: originY + CGFloat(rowIndex) * pixel,
                        width: pixel * 0.90,
                        height: pixel * 0.90
                    )
                    context.fill(
                        Path(rect),
                        with: .color(cell == 2 ? Color.black.opacity(0.86) : bodyColor)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A truthful block meter. Each lit cell always maps to one configured item.
struct AgentMeterSegmentedGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Int
    let total: Int
    var tint = AgentMeterTheme.signal
    var height: CGFloat = 5
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Rectangle()
                    .fill(index < clampedValue ? tint : Color.white.opacity(0.14))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: clampedValue)
        .accessibilityHidden(true)
    }

    private var clampedValue: Int {
        min(max(value, 0), max(total, 1))
    }
}

struct AgentMeterPixelRail: View {
    var tint = AgentMeterTheme.signal
    var segments = 8

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { _ in
                Rectangle().fill(tint)
            }
        }
        .frame(width: 96, height: 2)
        .accessibilityHidden(true)
    }
}
