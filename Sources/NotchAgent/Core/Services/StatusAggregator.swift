import Foundation

/// Pure functions that consolidate raw snapshots into UI-facing status.
/// Kept free of state so every rule is unit-testable.
enum StatusAggregator {
    static func attention(for snapshot: UsageSnapshot, settings: AppSettings) -> AttentionLevel {
        var worst: AttentionLevel = .normal
        if snapshot.health == .parseError || snapshot.health == .degraded {
            worst = .warning
        }
        // API-reported limit state is authoritative and overrides percent math.
        switch snapshot.quotaStatus {
        case .blocked: worst = .critical
        case .warning: worst = max(worst, .warning)
        default: break
        }
        let percents = [snapshot.session?.usedPercent, snapshot.weekly?.usedPercent].compactMap(\.self)
        for percent in percents {
            if percent >= settings.criticalThresholdPercent {
                worst = max(worst, .critical)
            } else if percent >= settings.warningThresholdPercent {
                worst = max(worst, .warning)
            }
        }
        return worst
    }

    static func overallAttention(snapshots: [ProviderID: UsageSnapshot], settings: AppSettings) -> AttentionLevel {
        snapshots.values
            .map { attention(for: $0, settings: settings) }
            .max() ?? .normal
    }

    /// Favorite first; otherwise the provider with the most recent activity.
    static func primaryProvider(snapshots: [ProviderID: UsageSnapshot], settings: AppSettings) -> ProviderID? {
        if let favorite = settings.favoriteProvider,
           let snapshot = snapshots[favorite], snapshot.health.isUsable {
            return favorite
        }
        return snapshots.values
            .filter { $0.health.isUsable }
            .max { ($0.lastActivityAt ?? .distantPast) < ($1.lastActivityAt ?? .distantPast) }?
            .provider
    }

    /// Alerts emitted when a provider crosses into a worse attention level.
    static func transitionAlerts(
        old: [ProviderID: UsageSnapshot],
        new snapshot: UsageSnapshot,
        settings: AppSettings
    ) -> [ProviderAlert] {
        let previous = old[snapshot.provider].map { attention(for: $0, settings: settings) } ?? .normal
        let current = attention(for: snapshot, settings: settings)
        guard current > previous else { return [] }

        let percentText = [snapshot.session?.usedPercent, snapshot.weekly?.usedPercent]
            .compactMap(\.self)
            .max()
            .map { " (\(Format.percent($0)))" } ?? ""
        return [ProviderAlert(
            provider: snapshot.provider,
            level: current,
            message: "\(snapshot.provider.displayName) entered \(current.label.lowercased())\(percentText)"
        )]
    }
}
