import SwiftUI

extension AttentionLevel {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

extension ProviderHealth {
    var badgeText: String {
        switch self {
        case .ok: "OK"
        case .degraded: "Degraded"
        case .parseError: "Parse error"
        case .notInstalled: "Not installed"
        case .noData: "No data"
        }
    }

    var badgeColor: Color {
        switch self {
        case .ok: .green
        case .degraded, .parseError: .orange
        case .notInstalled, .noData: .secondary.opacity(0.8)
        }
    }
}

struct AttentionDot: View {
    let level: AttentionLevel

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: 7, height: 7)
            .shadow(color: level.color.opacity(level == .normal ? 0 : 0.7), radius: 3)
    }
}

/// Thin horizontal progress bar for quota percentages.
struct UsageBar: View {
    let percent: Double
    var tint: Color = Theme.textPrimary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.socket)
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, proxy.size.width * min(percent, 100) / 100))
            }
        }
        .frame(height: 3)
    }
}

/// Minimal sparkline drawn from raw values (auto-normalized).
struct SparklineView: View {
    let values: [Double]
    var tint: Color = Theme.textSecondary

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let maxValue = max(values.max() ?? 1, 1)
            let stepX = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height - CGFloat(value / maxValue) * (size.height - 1) - 0.5
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(tint), lineWidth: 1.2)
        }
    }
}
