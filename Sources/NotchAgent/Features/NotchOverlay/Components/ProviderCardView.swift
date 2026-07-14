import SwiftUI

/// One provider inside the expanded notch panel, stick-style: giant
/// "% left" numeral, segmented tank meter, reset countdown.
struct ProviderCardView: View {
    let snapshot: UsageSnapshot?
    let provider: ProviderID
    let attention: AttentionLevel
    let refreshState: RefreshState
    var burn: BurnRate.Projection?

    @Environment(UsageStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let snapshot, snapshot.health.isUsable {
                metrics(snapshot)
            } else {
                unavailable
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    attention == .normal ? Theme.hairline : attention.color.opacity(0.45),
                    lineWidth: 1
                )
        )
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: provider.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
            GaugeLabel(text: provider.shortName, color: Theme.textSecondary, size: 9)
            Spacer()
            if let chip = quotaChip {
                StatusPill(text: chip.text, color: chip.color)
            }
        }
    }

    private var quotaChip: (text: String, color: Color)? {
        switch snapshot?.quotaStatus {
        case .blocked: ("Blocked", Theme.danger)
        case .warning: ("Near limit", Theme.warning)
        default: nil
        }
    }

    @ViewBuilder
    private func metrics(_ snapshot: UsageSnapshot) -> some View {
        let settings = store.settings

        VStack(alignment: .leading, spacing: 7) {
            if let metric = GaugeMetric.from(snapshot) {
                let tint = Theme.riskTint(
                    used: metric.used,
                    projectedToRunOut: !metric.isWeekly && burn?.exhaustsAt != nil,
                    warningAt: settings.warningThresholdPercent,
                    criticalAt: settings.criticalThresholdPercent
                )
                Text("\(Int(metric.remaining.rounded()))%")
                    .font(Theme.numeral(30))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                GaugeLabel(text: metric.isWeekly ? "OF WEEKLY LIMIT LEFT" : "OF 5H SESSION LEFT")
                SegmentedMeter(percent: metric.remaining, segments: 12, tint: tint, height: 8)

                if let resets = resetDate(snapshot, metric: metric) {
                    VStack(alignment: .leading, spacing: 2) {
                        GaugeLabel(text: "RESETS • \(Format.time(resets))")
                        Text(Format.countdown(to: resets))
                            .font(Theme.body(15, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            } else if let tokens = fallbackTokens(snapshot) {
                Text(Format.tokens(tokens))
                    .font(Theme.numeral(24))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                GaugeLabel(text: "TOKENS · NO LIMIT DATA")
            }

            if let usage = usageLine(snapshot) {
                Text(usage)
                    .font(Theme.body(9.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            if let verdict = BurnRate.verdict(burn) {
                Text(verdict)
                    .font(Theme.body(9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(burn?.exhaustsAt != nil ? Theme.warning : Theme.caution)
                    .lineLimit(1)
            }
            if snapshot.session?.usedPercent == nil, snapshot.weekly?.usedPercent == nil,
               let note = snapshot.note {
                Text(note)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(2)
            }
        }
    }

    private func resetDate(_ snapshot: UsageSnapshot, metric: GaugeMetric) -> Date? {
        metric.isWeekly ? snapshot.weekly?.resetsAt : snapshot.session?.resetsAt
    }

    private func fallbackTokens(_ snapshot: UsageSnapshot) -> Int? {
        if let tokens = snapshot.session?.tokens.total, tokens > 0 { return tokens }
        if let tokens = snapshot.weekly?.tokens.total, tokens > 0 { return tokens }
        return nil
    }

    private func usageLine(_ snapshot: UsageSnapshot) -> String? {
        let metric = GaugeMetric.from(snapshot)
        let tokens: Int?
        let cost: CostEstimate?
        if metric?.isWeekly == true {
            tokens = snapshot.weekly?.tokens.total
            cost = snapshot.weekly?.cost
        } else {
            tokens = snapshot.session?.tokens.total
            cost = snapshot.session?.cost
        }
        var parts: [String] = []
        if let tokens, tokens > 0 {
            parts.append(Format.tokens(tokens))
        }
        if let cost, cost.amountUSD >= 0.01 {
            parts.append("~" + Format.usd(cost.amountUSD))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot?.health.badgeText ?? "Waiting for data…")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textDim)
            if let note = snapshot?.note {
                Text(note)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(3)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let health = snapshot?.health {
                StatusPill(text: health.badgeText, color: healthColor(health))
            }
            Spacer()
            GaugeLabel(text: refreshText, color: Theme.textFaint, size: 8)
        }
    }

    private func healthColor(_ health: ProviderHealth) -> Color {
        switch health {
        case .ok: Theme.ok
        case .degraded, .parseError: Theme.warning
        case .notInstalled, .noData: Theme.textDim
        }
    }

    private var refreshText: String {
        switch refreshState {
        case .refreshing: "syncing…"
        case .success(let date): Format.relative(date)
        case .failure(let date, _): "failed \(Format.relative(date))"
        case .idle: ""
        }
    }
}
