import Foundation

public struct TokenUsage: Codable, Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheWrite: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public var total: Int { input + output + cacheWrite + cacheRead }

    public static let zero = TokenUsage()

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }

    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) { lhs = lhs + rhs }
}

/// Always local math over public pricing tables — never presented as billing truth.
public struct CostEstimate: Codable, Sendable, Equatable {
    public var amountUSD: Double

    public init(amountUSD: Double) { self.amountUSD = amountUSD }

    public static func + (lhs: CostEstimate, rhs: CostEstimate) -> CostEstimate {
        CostEstimate(amountUSD: lhs.amountUSD + rhs.amountUSD)
    }
}

/// A quota scoped to something narrower than the provider's headline number —
/// one specific model (Codex's per-model weekly cap, Claude's separately
/// metered Fable 5 pool) rather than the "all models" aggregate. Providers
/// that only ever expose one number never populate these; the headline
/// gauge always stays the aggregate/worst-case value.
public struct NamedQuota: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    /// 0–100.
    public var usedPercent: Double
    public var resetsAt: Date?

    public var id: String { name }

    public init(name: String, usedPercent: Double, resetsAt: Date? = nil) {
        self.name = name
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Usage inside the provider's current rate-limit session window (e.g. 5h block).
public struct SessionUsage: Codable, Sendable, Equatable {
    public var tokens: TokenUsage
    public var cost: CostEstimate?
    public var startedAt: Date?
    public var resetsAt: Date?
    /// 0–100. nil when the provider exposes no session limit locally.
    public var usedPercent: Double?
    /// Other scopes sharing this window (e.g. a model with its own separate
    /// cap) — never shown as the headline number, only in per-model detail.
    public var namedQuotas: [NamedQuota]?
    /// Token usage broken down by model, scoped to this session window —
    /// the only data granular enough to answer "what would this session
    /// have cost under a different model?" (`UsageSnapshot.modelBreakdown`
    /// is a flat total over the whole 8-day lookback, not this window).
    public var modelTokens: [String: TokenUsage]?
    /// Whether `usedPercent` came from the provider's authoritative quota
    /// probe (dollar-cost-correlated) rather than the local token-budget
    /// fallback (a rough token-count approximation). Features that scale
    /// `usedPercent` by a dollar-based ratio (e.g. burn-chart alternates)
    /// must gate on this specifically — `UsageSnapshot.quotaStatus` is non-nil
    /// whenever EITHER the session OR weekly probe percent is present, which
    /// is not the same question. Defaults false so "no session at all" and
    /// "budget fallback" both read as not-quota-backed, never ambiguous.
    public var usedPercentIsFromQuota: Bool

    public init(
        tokens: TokenUsage = .zero,
        cost: CostEstimate? = nil,
        startedAt: Date? = nil,
        resetsAt: Date? = nil,
        usedPercent: Double? = nil,
        namedQuotas: [NamedQuota]? = nil,
        modelTokens: [String: TokenUsage]? = nil,
        usedPercentIsFromQuota: Bool = false
    ) {
        self.tokens = tokens
        self.cost = cost
        self.startedAt = startedAt
        self.resetsAt = resetsAt
        self.usedPercent = usedPercent
        self.namedQuotas = namedQuotas
        self.modelTokens = modelTokens
        self.usedPercentIsFromQuota = usedPercentIsFromQuota
    }
}

/// Authoritative rate-limit state reported by the provider's API
/// (`anthropic-ratelimit-unified-status` for Claude).
public enum QuotaStatus: String, Codable, Sendable, Equatable {
    case ok
    case warning
    case blocked
}

public struct HourlyTotal: Codable, Sendable, Equatable, Identifiable {
    public var hour: Date
    public var tokens: Int

    public var id: Date { hour }

    public init(hour: Date, tokens: Int) {
        self.hour = hour
        self.tokens = tokens
    }
}

public struct DailyTotal: Codable, Sendable, Equatable, Identifiable {
    public var day: Date
    public var tokens: Int
    public var costUSD: Double

    public var id: Date { day }

    public init(day: Date, tokens: Int, costUSD: Double) {
        self.day = day
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

/// Trailing 7-day usage (or the provider's own weekly window when it exposes one).
public struct WeeklyUsage: Codable, Sendable, Equatable {
    public var tokens: TokenUsage
    public var cost: CostEstimate?
    /// 0–100. nil when no weekly limit is known.
    public var usedPercent: Double?
    public var resetsAt: Date?
    public var dailyTotals: [DailyTotal]
    /// Per-hour activity used for the "hourly rhythm" chart. Optional so old
    /// persisted snapshots keep decoding.
    public var hourlyTotals: [HourlyTotal]?
    /// Other scopes sharing this window (e.g. a model with its own separate
    /// weekly cap) — never shown as the headline number, only in per-model detail.
    public var namedQuotas: [NamedQuota]?

    public init(
        tokens: TokenUsage = .zero,
        cost: CostEstimate? = nil,
        usedPercent: Double? = nil,
        resetsAt: Date? = nil,
        dailyTotals: [DailyTotal] = [],
        hourlyTotals: [HourlyTotal]? = nil,
        namedQuotas: [NamedQuota]? = nil
    ) {
        self.tokens = tokens
        self.cost = cost
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.dailyTotals = dailyTotals
        self.hourlyTotals = hourlyTotals
        self.namedQuotas = namedQuotas
    }
}

/// Aggregated usage for one model family (from local transcripts).
public struct ModelUsage: Codable, Sendable, Equatable, Identifiable {
    public var model: String
    public var tokens: Int
    public var costUSD: Double

    public var id: String { model }

    public init(model: String, tokens: Int, costUSD: Double) {
        self.model = model
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

public enum ModelProbeStatus: String, Codable, Sendable, Equatable {
    case ok
    case limited
    case error
}

/// Live per-model health from a rotating 1-token probe (stick-style).
public struct ModelHealth: Codable, Sendable, Equatable, Identifiable {
    public var model: String
    public var status: ModelProbeStatus
    public var latencyMs: Int?
    public var checkedAt: Date

    public var id: String { model }

    public init(model: String, status: ModelProbeStatus, latencyMs: Int?, checkedAt: Date) {
        self.model = model
        self.status = status
        self.latencyMs = latencyMs
        self.checkedAt = checkedAt
    }
}

/// The one gauge that matters everywhere: how much of the limit is LEFT.
/// Session window takes precedence; weekly is the fallback.
public struct GaugeMetric: Sendable, Equatable {
    public let used: Double
    public let isWeekly: Bool

    public var remaining: Double { max(0, 100 - used) }

    public init(used: Double, isWeekly: Bool) {
        self.used = used
        self.isWeekly = isWeekly
    }

    public static func from(_ snapshot: UsageSnapshot?) -> GaugeMetric? {
        // The API's "rejected" status is more authoritative than any percent
        // math: if the account is blocked, the gauge must show empty — never
        // a calm green number that contradicts a BLOCKED badge on the same
        // card. This also makes the low-fuel takeover and the runner's game
        // over fire together with the badge, instead of racing against it.
        if snapshot?.quotaStatus == .blocked {
            let isWeekly = snapshot?.session?.usedPercent == nil && snapshot?.weekly?.usedPercent != nil
            return GaugeMetric(used: 100, isWeekly: isWeekly)
        }
        if let percent = snapshot?.session?.usedPercent {
            return GaugeMetric(used: percent, isWeekly: false)
        }
        if let percent = snapshot?.weekly?.usedPercent {
            return GaugeMetric(used: percent, isWeekly: true)
        }
        return nil
    }
}

/// Normalized output of every provider — the only shape the UI ever consumes.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var provider: ProviderID
    public var capturedAt: Date
    public var health: ProviderHealth
    public var session: SessionUsage?
    public var weekly: WeeklyUsage?
    public var activeModel: String?
    public var lastActivityAt: Date?
    /// Human-readable caveat (e.g. "token data unavailable for this CLI").
    public var note: String?
    /// API-reported limit state (allowed / warning / rejected), when available.
    public var quotaStatus: QuotaStatus?
    /// Per-model usage over the lookback window (local transcripts).
    public var modelBreakdown: [ModelUsage]?
    /// Live per-model probe results, when the API probe is enabled.
    public var modelHealth: [ModelHealth]?
    /// Per-account cost, balance, or quota data from opt-in API monitors.
    public var accountUsage: [APIAccountUsage]?

    public init(
        provider: ProviderID,
        capturedAt: Date = Date(),
        health: ProviderHealth,
        session: SessionUsage? = nil,
        weekly: WeeklyUsage? = nil,
        activeModel: String? = nil,
        lastActivityAt: Date? = nil,
        note: String? = nil,
        quotaStatus: QuotaStatus? = nil,
        modelBreakdown: [ModelUsage]? = nil,
        modelHealth: [ModelHealth]? = nil,
        accountUsage: [APIAccountUsage]? = nil
    ) {
        self.provider = provider
        self.capturedAt = capturedAt
        self.health = health
        self.session = session
        self.weekly = weekly
        self.activeModel = activeModel
        self.lastActivityAt = lastActivityAt
        self.note = note
        self.quotaStatus = quotaStatus
        self.modelBreakdown = modelBreakdown
        self.modelHealth = modelHealth
        self.accountUsage = accountUsage
    }
}
