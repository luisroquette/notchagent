import SwiftUI

/// Glanceable strip with fixed, labeled sides: CLAUDE on the left wing, CODEX
/// on the right. Every number is self-explanatory — provider name on top,
/// "% left of which window" below. No decoding required at a glance.
struct NotchCompactView: View {
    @Environment(UsageStore.self) private var store
    @Environment(NotchViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 0) {
            wing(for: .claudeCode, mirrored: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.geometry.hasNotch {
                Color.clear
                    .frame(width: viewModel.geometry.notchWidth)
            } else {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 10)
            }
            HStack(spacing: 8) {
                wing(for: .codex, mirrored: true)
                AttentionDot(level: store.overallAttention)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: viewModel.compactSize.height)
    }

    @ViewBuilder
    private func wing(for provider: ProviderID, mirrored: Bool) -> some View {
        let snapshot = store.snapshots[provider]
        let metric = GaugeMetric.from(snapshot)

        VStack(alignment: mirrored ? .trailing : .leading, spacing: 2.5) {
            // Row 1: who + which window, spelled out.
            HStack(spacing: 4) {
                GaugeLabel(text: provider.shortName, color: Theme.textSecondary, size: 8)
                if let metric {
                    GaugeLabel(
                        text: metric.isWeekly ? "WK LEFT" : "5H LEFT",
                        color: Theme.textFaint,
                        size: 6.5
                    )
                }
            }

            // Row 2: the number + draining tank meter, mirrored outward.
            if let metric {
                let tint = Theme.riskTint(
                    used: metric.used,
                    projectedToRunOut: !metric.isWeekly
                        && store.burnProjection(for: provider)?.exhaustsAt != nil,
                    warningAt: store.settings.warningThresholdPercent,
                    criticalAt: store.settings.criticalThresholdPercent
                )
                HStack(spacing: 6) {
                    if mirrored {
                        meter(metric, tint: tint)
                        percentText(metric, tint: tint)
                    } else {
                        percentText(metric, tint: tint)
                        meter(metric, tint: tint)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Text(compactFallback(snapshot))
                        .font(Theme.body(11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                    GaugeLabel(text: "TOKENS", color: Theme.textFaint, size: 6.5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(provider: provider, metric: metric))
    }

    private func accessibilitySummary(provider: ProviderID, metric: GaugeMetric?) -> String {
        guard let metric else { return "\(provider.displayName): no limit data" }
        let window = metric.isWeekly ? "weekly limit" : "5 hour session"
        return "\(provider.displayName): \(Int(metric.remaining.rounded())) percent of the \(window) left"
    }

    private func percentText(_ metric: GaugeMetric, tint: Color) -> some View {
        Text("\(Int(metric.remaining.rounded()))%")
            .font(Theme.numeral(15))
            .monospacedDigit()
            .foregroundStyle(tint)
            .contentTransition(.numericText())
    }

    private func meter(_ metric: GaugeMetric, tint: Color) -> some View {
        SegmentedMeter(percent: metric.remaining, segments: 8, tint: tint, height: 4, spacing: 1.5)
            .frame(width: 44)
    }

    private func compactFallback(_ snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "—" }
        if let tokens = snapshot.session?.tokens.total, tokens > 0 {
            return Format.tokens(tokens)
        }
        if let tokens = snapshot.weekly?.tokens.total, tokens > 0 {
            return Format.tokens(tokens)
        }
        return snapshot.health.isUsable ? "idle" : "—"
    }
}
