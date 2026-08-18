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

    /// Secondary window shown under the headline when the provider has BOTH
    /// a session scope and a weekly scope (e.g. Claude/Anthropic plans with a
    /// 5h window AND a weekly cap). Nil when the headline already IS the
    /// weekly, or when no official weekly percent exists.
    struct SecondaryScope: Equatable {
        let usedPercent: Double
        let resetsAt: Date?
    }

    static func secondaryScope(_ snapshot: UsageSnapshot) -> SecondaryScope? {
        guard snapshot.session?.usedPercent != nil,
              let weekly = snapshot.weekly?.usedPercent else { return nil }
        return SecondaryScope(usedPercent: weekly, resetsAt: snapshot.weekly?.resetsAt)
    }

    /// Plans that report only a weekly cap (Codex Pro: the rollout carries a
    /// single 7-day window, no 5h/daily window at all) get the SAME two-block
    /// scheme as Claude, inverted: the current session's real tokens take the
    /// headline, and the weekly cap becomes the secondary block. No daily
    /// percent is ever fabricated.
    struct SessionPrimary: Equatable {
        let tokens: TokenUsage
        let startedAt: Date?
    }

    static func sessionPrimaryLayout(_ snapshot: UsageSnapshot) -> SessionPrimary? {
        guard let metric = GaugeMetric.from(snapshot), metric.isWeekly,
              let session = snapshot.session, session.tokens.total > 0 else { return nil }
        return SessionPrimary(tokens: session.tokens, startedAt: session.startedAt)
    }

    /// "~" prefix when the 5h percent is a local budget estimate, not the
    /// provider's authoritative quota.
    static func sessionPercentPrefix(_ snapshot: UsageSnapshot) -> String {
        snapshot.session?.usedPercentIsFromQuota == false ? "~" : ""
    }

    static func sessionLabel(_ snapshot: UsageSnapshot, metric: GaugeMetric) -> String {
        guard !metric.isWeekly else { return "OF WEEKLY LIMIT LEFT" }
        return snapshot.session?.usedPercentIsFromQuota == false
            ? "OF 5H SESSION LEFT · ESTIMATED"
            : "OF 5H SESSION LEFT"
    }

    private var header: some View {
        HStack(spacing: 5) {
            providerGlyph
            GaugeLabel(text: provider.shortName, color: Theme.textSecondary, size: 9)
            Spacer()
            if let chip = quotaChip {
                StatusPill(text: chip.text, color: chip.color)
            }
        }
    }

    /// Brand glyph per provider: the Claude mascot (active model family) and
    /// the OpenAI knot, so the two cards are told apart at a glance.
    @ViewBuilder
    private var providerGlyph: some View {
        switch provider {
        case .claudeCode:
            ClaudeMascot(name: Self.mascotName(for: snapshot?.activeModel))
                .frame(width: 24, height: 24)
        case .codex:
            OpenAIGlyph()
                .frame(width: 24, height: 24)
        default:
            Image(systemName: provider.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Maps an active model name to its mascot family asset; unknown or
    /// missing models fall back to sonnet.
    static func mascotName(for model: String?) -> String {
        let families = ["fable", "opus", "haiku", "sonnet"]
        let lower = model?.lowercased() ?? ""
        for family in families where lower.contains(family) {
            return "claude-\(family)"
        }
        return "claude-sonnet"
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
                if metric.isWeekly, let sessionPrimary = Self.sessionPrimaryLayout(snapshot) {
                    // Weekly-only plan: the current session's real tokens take
                    // the headline (same "current window" concept as Claude's
                    // 5h percent, without fabricating one), and the weekly cap
                    // drops to the secondary block below.
                    Text(Format.tokens(sessionPrimary.tokens.total))
                        .font(Theme.numeral(24))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    GaugeLabel(text: "CURRENT SESSION · NO DAILY CAP REPORTED")
                    if let startedAt = sessionPrimary.startedAt {
                        GaugeLabel(text: "STARTED \(Format.relative(startedAt))", color: Theme.textFaint, size: 8)
                    }
                    if let weeklyPercent = snapshot.weekly?.usedPercent {
                        weeklySecondaryBlock(
                            secondary: SecondaryScope(usedPercent: weeklyPercent, resetsAt: snapshot.weekly?.resetsAt),
                            warningAt: settings.warningThresholdPercent,
                            criticalAt: settings.criticalThresholdPercent
                        )
                    }
                } else {
                    let tint = Theme.riskTint(
                        used: metric.used,
                        projectedToRunOut: !metric.isWeekly && burn?.exhaustsAt != nil,
                        warningAt: settings.warningThresholdPercent,
                        criticalAt: settings.criticalThresholdPercent
                    )
                    Text("\(Self.sessionPercentPrefix(snapshot))\(Int(metric.remaining.rounded()))%")
                        .font(Theme.numeral(30))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                    GaugeLabel(text: Self.sessionLabel(snapshot, metric: metric))
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

                    // Secondary window: same visual pattern as the headline,
                    // smaller scale — the weekly cap under the 5h session window.
                    if !metric.isWeekly, let secondary = Self.secondaryScope(snapshot) {
                        weeklySecondaryBlock(
                            secondary: secondary,
                            warningAt: settings.warningThresholdPercent,
                            criticalAt: settings.criticalThresholdPercent
                        )
                    }
                }
            } else if let tokens = fallbackTokens(snapshot) {
                // No official quota exists for this window (e.g. Codex plans
                // that only expose a weekly %) — show the SAME "current
                // window" concept the percent-based cards show, just in
                // tokens instead of a fabricated percentage.
                Text(Format.tokens(tokens))
                    .font(Theme.numeral(24))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                GaugeLabel(text: "CURRENT SESSION · NO CAP REPORTED")
                if let startedAt = snapshot.session?.startedAt {
                    GaugeLabel(text: "STARTED \(Format.relative(startedAt))", color: Theme.textFaint, size: 8)
                }
            }

            if let usage = usageLine(snapshot) {
                Text(usage)
                    .font(Theme.body(9.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            if let hint = namedQuotaHint(snapshot) {
                Text(hint)
                    .font(Theme.body(8.5))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(2)
            } else {
                ForEach(namedQuotas(snapshot).prefix(2)) { quota in
                    namedQuotaLine(quota)
                }
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

    /// Secondary scopes sharing the headline window (e.g. Codex's per-model
    /// weekly cap, Claude's Fable 5 pool) — most headroom FIRST. The
    /// headline number above already answers "am I in trouble"; this answers
    /// "where do I still have room to work", so it must surface what's still
    /// usable, not repeat the worst case.
    private func namedQuotas(_ snapshot: UsageSnapshot) -> [NamedQuota] {
        let quotas = snapshot.session?.namedQuotas ?? snapshot.weekly?.namedQuotas ?? []
        return quotas.sorted { $0.usedPercent < $1.usedPercent }
    }

    /// When every known scope is exhausted, listing them all at "0% left"
    /// answers nothing — point at where to actually check for a model with
    /// room, since a scope NotchAgent has never seen locally (never used
    /// this week) simply isn't in this data at all.
    private func namedQuotaHint(_ snapshot: UsageSnapshot) -> String? {
        let quotas = namedQuotas(snapshot)
        guard !quotas.isEmpty, quotas.allSatisfy({ $0.usedPercent >= 99.5 }) else { return nil }
        let portal = snapshot.provider == .codex
            ? "chatgpt.com/codex/settings/usage"
            : "claude.ai/settings/usage"
        return "Every model seen locally this week is exhausted · check \(portal) for one that isn't"
    }

    private func namedQuotaLine(_ quota: NamedQuota) -> some View {
        let remaining = max(0, 100 - quota.usedPercent)
        return HStack(spacing: 4) {
            Text(quota.name)
                .font(Theme.body(8.5))
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(Int(remaining.rounded()))% left")
                .font(Theme.body(8.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.riskTint(
                    used: quota.usedPercent,
                    projectedToRunOut: false,
                    warningAt: store.settings.warningThresholdPercent,
                    criticalAt: store.settings.criticalThresholdPercent
                ))
        }
    }

    private func resetDate(_ snapshot: UsageSnapshot, metric: GaugeMetric) -> Date? {
        metric.isWeekly ? snapshot.weekly?.resetsAt : snapshot.session?.resetsAt
    }

    /// The weekly cap rendered as a secondary block — smaller scale of the
    /// headline pattern, shared by the Claude layout (under the 5h percent)
    /// and the Codex layout (under the session-token headline).
    @ViewBuilder
    private func weeklySecondaryBlock(secondary: SecondaryScope, warningAt: Double, criticalAt: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            let tint = Theme.riskTint(
                used: secondary.usedPercent,
                projectedToRunOut: false,
                warningAt: warningAt,
                criticalAt: criticalAt
            )
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(max(0, 100 - secondary.usedPercent).rounded()))%")
                    .font(Theme.numeral(15))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                GaugeLabel(text: "OF WEEKLY LIMIT LEFT", color: Theme.textFaint, size: 8)
                Spacer(minLength: 0)
            }
            SegmentedMeter(percent: max(0, 100 - secondary.usedPercent), segments: 12, tint: tint, height: 4)
            if let resets = secondary.resetsAt {
                HStack(spacing: 5) {
                    GaugeLabel(text: "RESETS • \(Format.time(resets))", color: Theme.textFaint, size: 8)
                    Text(Format.countdown(to: resets))
                        .font(Theme.body(12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.top, 1)
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
        case .stale(let date): "stale \(Format.relative(date))"
        case .failure(let date, _): "failed \(Format.relative(date))"
        case .idle: ""
        }
    }
}
