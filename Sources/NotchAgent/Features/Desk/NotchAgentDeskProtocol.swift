import Foundation

enum NotchAgentDeskProtocol {
    static let product = "NotchAgent Desk"
    static let protocolMajor: UInt8 = 1
    static let protocolMinor: UInt8 = 2
    static let maximumPayloadBytes = 16 * 1_024

    enum FrameType: UInt8, Codable, Sendable {
        case hello = 1
        case helloAcknowledgement = 2
        case snapshot = 3
        case heartbeat = 4
        case deviceTelemetry = 5
    }
}

struct DeskHelloAcknowledgement: Codable, Sendable, Equatable {
    var product: String
    var protocolMajor: UInt8
    var protocolMinor: UInt8
    var nonce: UInt32
    var firmwareVersion: String?
}

struct NotchAgentDeskConnectionState: Sendable, Equatable {
    enum Phase: String, Codable, Sendable {
        case disabled
        case searching
        case handshaking
        case connected
        case incompatible
    }

    var phase: Phase
    var path: String?
    var firmwareVersion: String?
    var protocolMajor: UInt8?
    var protocolMinor: UInt8?
    var telemetry: DeskDeviceTelemetry? = nil

    static let disabled = Self(phase: .disabled)
    static let searching = Self(phase: .searching)
}

struct DeskDeviceTelemetry: Codable, Sendable, Equatable {
    var firmwareVersion: String
    var uptimeSeconds: UInt64
    var freeHeapBytes: UInt32
    var minimumFreeHeapBytes: UInt32
    var framesPerSecond: Double
    var resetReason: String
    var invalidFrameCount: UInt32
    var handshakeCount: UInt32
    var touchCount: UInt32
    var touchInterruptCount: UInt32? = nil
    var touchReadErrorCount: UInt32? = nil
    var touchPollAttemptCount: UInt32? = nil
    var touchPollTouchCount: UInt32? = nil
    var touchControllerPresent: Bool? = nil
    var lastTouchLatencyMs: Double
    var maximumTouchLatencyMs: Double
}

struct DeskHello: Codable, Sendable, Equatable {
    var product: String
    var protocolMajor: UInt8
    var protocolMinor: UInt8
    var nonce: UInt32
}

struct DeskSnapshot: Codable, Sendable, Equatable {
    struct Provider: Codable, Sendable, Equatable {
        enum Window: String, Codable, Sendable { case session, weekly }

        var id: ProviderID
        var health: ProviderHealth
        var refreshState: String
        var remainingPercent: Double?
        var window: Window?
        var resetsAt: Date?
        var tokens: Int
        var attention: AttentionLevel
        var burnPercentPerHour: Double?
        var exhaustsAt: Date?
    }

    struct RhythmPoint: Codable, Sendable, Equatable {
        var hour: Int
        var tokens: Int
    }

    struct BurnPoint: Codable, Sendable, Equatable {
        var ageSeconds: Int
        var usedPercent: Double
    }

    struct Model: Codable, Sendable, Equatable {
        var name: String
        var tokens: Int
        var status: ModelProbeStatus?
        var latencyMs: Int?
    }

    struct ModelAlternate: Codable, Sendable, Equatable {
        /// "Haiku"/"Sonnet"/"Opus"/"Fable" — matches ModelProjection.shortName(for:).
        var shortName: String
        /// costUSD(alternate, sessionTokens) / costUSD(dominant, sessionTokens).
        /// Firmware multiplies each burnHistory.usedPercent by this and clamps
        /// to 100 to draw the alternate's line — see ModelProjection.Alternate.
        var priceRatio: Double
    }

    var product: String
    var protocolMajor: UInt8
    var protocolMinor: UInt8
    var generatedAt: Date
    var overallAttention: AttentionLevel
    var isPaused: Bool
    var providers: [Provider]
    var burnHistory: [BurnPoint]
    var rhythm: [RhythmPoint]
    var models: [Model]
    var dominantModelShortName: String?
    var modelAlternates: [ModelAlternate]?
    var alertThresholds: [Int] = ThresholdAlerts.defaultLevels
    var runnerEnabled: Bool = true
    var ambientRecommendation: DeskAmbientRecommendation? = nil
}

enum DeskSnapshotFactory {
    @MainActor
    static func make(from store: UsageStore, now: Date = Date()) -> DeskSnapshot {
        let orderedProviderIDs = ([store.primaryProvider].compactMap { $0 }
            + ProviderID.allCases.filter { $0 != store.primaryProvider })
            .filter { $0 != .apiAccounts }
        let providers = orderedProviderIDs.compactMap { provider -> DeskSnapshot.Provider? in
            guard let snapshot = store.snapshots[provider] else { return nil }
            let gauge = GaugeMetric.from(snapshot)
            // Percent history currently records the 5h session only. Never
            // label that slope as a weekly-window projection.
            let projection = gauge?.isWeekly == false ? store.burnProjection(for: provider) : nil
            return DeskSnapshot.Provider(
                id: provider,
                health: snapshot.health,
                refreshState: refreshStateLabel(store.refreshStates[provider] ?? .idle),
                remainingPercent: gauge.map { clamp($0.remaining, lower: 0, upper: 100) },
                window: gauge.map { $0.isWeekly ? .weekly : .session },
                resetsAt: gauge?.isWeekly == true ? snapshot.weekly?.resetsAt : snapshot.session?.resetsAt,
                tokens: tokenTotal(gauge?.isWeekly == true ? snapshot.weekly?.tokens : snapshot.session?.tokens),
                attention: store.attention(for: provider),
                burnPercentPerHour: projection.map { clamp($0.percentPerHour, lower: 0, upper: 10_000) },
                exhaustsAt: projection?.exhaustsAt
            )
        }

        let rhythm = aggregateRhythm(store.snapshots.values)
        let burnHistory = aggregateBurnHistory(store: store, now: now)
        let models = aggregateModels(store.snapshots.values)
        let (dominantModelShortName, modelAlternates) = modelBurnAlternates(store: store)
        return DeskSnapshot(
            product: NotchAgentDeskProtocol.product,
            protocolMajor: NotchAgentDeskProtocol.protocolMajor,
            protocolMinor: NotchAgentDeskProtocol.protocolMinor,
            generatedAt: now,
            overallAttention: store.overallAttention,
            isPaused: store.isPaused,
            providers: Array(providers.prefix(8)),
            burnHistory: burnHistory,
            rhythm: rhythm,
            models: models,
            dominantModelShortName: dominantModelShortName,
            modelAlternates: modelAlternates,
            alertThresholds: ThresholdAlerts.normalized(store.settings.quotaAlertThresholdPercents),
            runnerEnabled: store.settings.runnerEnabled,
            ambientRecommendation: NotchAgentDeskAmbientIntelligence.recommend(store: store, now: now)
        )
    }

    @MainActor
    private static func aggregateBurnHistory(store: UsageStore, now: Date) -> [DeskSnapshot.BurnPoint] {
        guard let primary = store.primaryProvider,
              let snapshot = store.snapshots[primary],
              GaugeMetric.from(snapshot)?.isWeekly == false
        else { return [] }
        return (store.percentHistory[primary] ?? [])
            .filter { now.timeIntervalSince($0.date) >= 0 && now.timeIntervalSince($0.date) <= 6 * 3_600 }
            .sorted { $0.date < $1.date }
            .suffix(48)
            .map {
                DeskSnapshot.BurnPoint(
                    ageSeconds: min(6 * 3_600, max(0, Int(now.timeIntervalSince($0.date).rounded()))),
                    usedPercent: clamp($0.percent, lower: 0, upper: 100)
                )
            }
    }

    @MainActor
    private static func modelBurnAlternates(
        store: UsageStore
    ) -> (dominantModelShortName: String?, modelAlternates: [DeskSnapshot.ModelAlternate]) {
        guard let primary = store.primaryProvider,
              let session = store.snapshots[primary]?.session,
              session.usedPercentIsFromQuota == true,
              let modelTokens = session.modelTokens,
              let dominant = ModelProjection.dominantModel(modelTokens: modelTokens)
        else { return (nil, []) }

        let alternates = ModelProjection.alternates(dominantModel: dominant, sessionTokens: session.tokens)
            .map { DeskSnapshot.ModelAlternate(shortName: $0.shortName, priceRatio: $0.priceRatio) }
        return (ModelProjection.shortName(for: dominant), alternates)
    }

    private static func aggregateRhythm(_ snapshots: Dictionary<ProviderID, UsageSnapshot>.Values) -> [DeskSnapshot.RhythmPoint] {
        var buckets = Array(repeating: 0, count: 24)
        for total in snapshots.compactMap(\.weekly?.hourlyTotals).flatMap({ $0 }) {
            let hour = Calendar.current.component(.hour, from: total.hour)
            buckets[hour] = saturatedAdd(buckets[hour], max(0, total.tokens))
        }
        return buckets.enumerated().map { .init(hour: $0.offset, tokens: $0.element) }
    }

    private static func aggregateModels(_ snapshots: Dictionary<ProviderID, UsageSnapshot>.Values) -> [DeskSnapshot.Model] {
        var usage: [String: Int] = [:]
        var health: [String: ModelHealth] = [:]
        for snapshot in snapshots {
            for model in snapshot.modelBreakdown ?? [] {
                let name = sanitizedModelName(model.model)
                usage[name] = saturatedAdd(usage[name] ?? 0, max(0, model.tokens))
            }
            for result in snapshot.modelHealth ?? [] {
                health[sanitizedModelName(result.model)] = result
            }
        }
        let names = Set(usage.keys).union(Set(health.keys)).filter { !$0.isEmpty }
        var models: [DeskSnapshot.Model] = []
        for name in names {
            models.append(DeskSnapshot.Model(
                    name: name,
                    tokens: usage[name] ?? 0,
                    status: health[name]?.status,
                    latencyMs: health[name]?.latencyMs.map { max(0, min($0, 120_000)) }
                ))
        }
        models.sort { lhs, rhs in lhs.tokens == rhs.tokens ? lhs.name < rhs.name : lhs.tokens > rhs.tokens }
        return Array(models.prefix(8))
    }

    private static func sanitizedModelName(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter {
            $0.value < 128 && (CharacterSet.alphanumerics.contains($0) || "-_. ".unicodeScalars.contains($0))
        }
        return String(String.UnicodeScalarView(allowed)).prefix(32).description
    }

    private static func refreshStateLabel(_ state: RefreshState) -> String {
        switch state {
        case .idle: "idle"
        case .refreshing: "refreshing"
        case .success: "updated"
        case .stale: "stale"
        case .failure: "error"
        }
    }


    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        guard value.isFinite else { return lower }
        return min(max(value, lower), upper)
    }

    private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }

    private static func tokenTotal(_ usage: TokenUsage?) -> Int {
        guard let usage else { return 0 }
        return [usage.input, usage.output, usage.cacheWrite, usage.cacheRead]
            .map { max(0, $0) }
            .reduce(0, saturatedAdd)
    }
}
