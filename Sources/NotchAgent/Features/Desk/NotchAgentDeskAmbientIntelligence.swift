import Foundation

struct DeskAmbientRecommendation: Codable, Sendable, Equatable {
    enum Page: String, Codable, Sendable {
        case now
        case burn
        case rhythm
        case models

        var index: Int {
            switch self {
            case .now: 0
            case .burn: 1
            case .rhythm: 2
            case .models: 3
            }
        }
    }

    var page: Page
    var reason: String
    var severity: AttentionLevel
}

enum NotchAgentDeskAmbientIntelligence {
    @MainActor
    static func recommend(store: UsageStore, now: Date = Date()) -> DeskAmbientRecommendation {
        if store.isPaused {
            return .init(page: .now, reason: "Refresh paused", severity: .warning)
        }

        let gauges = store.snapshots.values.compactMap { snapshot -> (UsageSnapshot, GaugeMetric)? in
            GaugeMetric.from(snapshot).map { (snapshot, $0) }
        }
        if let lowest = gauges.min(by: { $0.1.remaining < $1.1.remaining }), lowest.1.remaining <= 25 {
            return .init(
                page: .now,
                reason: "\(lowest.0.provider.displayName) has \(Int(lowest.1.remaining.rounded()))% left",
                severity: lowest.1.remaining <= 5 ? .critical : .warning
            )
        }

        if let provider = store.primaryProvider,
           store.burnProjection(for: provider)?.exhaustsAt != nil {
            return .init(page: .burn, reason: "Current pace may exhaust this window", severity: .warning)
        }

        let unhealthyModel = store.snapshots.values
            .flatMap { $0.modelHealth ?? [] }
            .contains { $0.status != .ok }
        if unhealthyModel {
            return .init(page: .models, reason: "A model needs attention", severity: .warning)
        }

        let recentlyActive = store.snapshots.values.contains {
            guard let activity = $0.lastActivityAt else { return false }
            return now.timeIntervalSince(activity) >= 0 && now.timeIntervalSince(activity) < 10 * 60
        }
        if recentlyActive {
            return .init(page: .rhythm, reason: "Active focus session", severity: .normal)
        }

        return .init(page: .now, reason: "Usage is stable", severity: .normal)
    }
}
