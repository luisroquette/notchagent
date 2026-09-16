import Foundation

/// Codex quota percentages come from the authenticated app-server when available;
/// rollout files provide local token totals and a read-only quota fallback.
struct CodexProvider: UsageProvider {
    let id = ProviderID.codex
    let capabilities: ProviderCapabilities = [
        .sessionTokens, .sessionPercent, .weeklyTokens, .weeklyPercent, .costEstimate, .resetSchedule,
    ]

    private let root: URL
    private let appServerRateLimits: CodexAppServerRateLimitReader?
    private let defaultModel = "gpt-5"
    private let cache = FileScanCache<CodexTokenInfo?>()
    private static let lookback: TimeInterval = 8 * 24 * 3600
    static let sharedLimitID = "codex"

    init(root: URL = AppPaths.home.appendingPathComponent(".codex/sessions")) {
        self.root = root
        let liveRoot = AppPaths.home.appendingPathComponent(".codex/sessions").standardizedFileURL
        appServerRateLimits = root.standardizedFileURL == liveRoot ? .shared : nil
    }

    init(root: URL, appServerRateLimits: CodexAppServerRateLimitReader) {
        self.root = root
        self.appServerRateLimits = appServerRateLimits
    }

    /// "rollout-2026-07-13T14-04-44-<uuid>.jsonl" → local start date.
    static func rolloutStart(from url: URL) -> Date? {
        let name = url.lastPathComponent
        guard name.hasPrefix("rollout-"), name.count >= 27 else { return nil }
        let stamp = String(name.dropFirst(8).prefix(19))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.date(from: stamp)
    }

    func detectInstallation() -> ProviderInstallation {
        FileManager.default.fileExists(atPath: root.path)
            ? .installed(dataPath: root.path)
            : .notInstalled
    }

    func fetchSnapshot(settings: AppSettings) async throws -> UsageSnapshot {
        let now = Date()
        let officialLimits = await appServerRateLimits?.currentLimits(now: now)
        let isInstalled: Bool
        if case .installed = detectInstallation() {
            isInstalled = true
        } else {
            isInstalled = false
        }
        guard isInstalled || officialLimits != nil else {
            return UsageSnapshot(provider: id, health: .notInstalled)
        }

        let files = recentFiles(under: root, ext: "jsonl", modifiedAfter: now.addingTimeInterval(-Self.lookback))
        if files.isEmpty, officialLimits == nil {
            return UsageSnapshot(provider: id, health: .noData, note: "No sessions in the last 8 days")
        }

        // Rollout totals are CUMULATIVE for the whole rollout, so window
        // membership must use when the rollout STARTED (from the filename),
        // not its last event — otherwise a 10h-old session whose last ping was
        // 5 minutes ago would dump 10h of tokens into the current 5h window.
        var perFile: [(info: CodexTokenInfo, start: Date)] = []
        var failedFiles = 0
        for url in files {
            do {
                if let info = try await cache.value(for: url, parse: { try CodexRolloutParser.latestTokenInfo(at: $0) }),
                   let info {
                    let start = Self.rolloutStart(from: url) ?? info.timestamp ?? .distantPast
                    perFile.append((info, start))
                }
            } catch {
                failedFiles += 1
                Log.providers.error("codex: failed to parse \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        await cache.prune(keeping: Set(files.map(\.path)))

        guard !perFile.isEmpty || officialLimits != nil else {
            return UsageSnapshot(provider: id, health: failedFiles > 0 ? .parseError : .noData)
        }

        // Newest rollout carries the freshest rate limits + current session totals.
        let latestEntry = perFile.max { ($0.info.timestamp ?? .distantPast) < ($1.info.timestamp ?? .distantPast) }
        let latest = latestEntry?.info
        // Window semantics vary per plan — classify by duration, never by
        // position — and NEVER trust a window whose reset already passed
        // (an idle weekend must not freeze Friday's 80% as today's truth).
        func freshWindow(_ window: CodexRateWindow?) -> CodexRateWindow? {
            guard let window else { return nil }
            if let resets = window.resetsAt, resets <= now { return nil }
            return window
        }
        // OpenAI identifies quota pools with `limit_id`. Standard Codex
        // models share `codex`; Spark is reported under its own ID. Model is
        // only activity metadata and must never define quota identity.
        var quotaScopes = Self.freshestQuotaScopesByLimitID(perFile)
        if let official = officialLimits {
            for (limitID, info) in official {
                quotaScopes[limitID] = QuotaScope(info: info, observedAt: info.timestamp ?? now)
            }
        }
        let sharedInfo = quotaScopes[Self.sharedLimitID]?.info
        let sessionWindow = freshWindow(sharedInfo?.sessionWindow)
        let weeklyWindow = freshWindow(sharedInfo?.weeklyWindow)
        let separateScopes = quotaScopes.filter { $0.key != Self.sharedLimitID }
        let namedSessionQuotas = separateScopes.compactMap { key, scope -> NamedQuota? in
            guard let window = freshWindow(scope.info.sessionWindow) else { return nil }
            return NamedQuota(
                name: Self.quotaName(for: scope.info, key: key),
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt
            )
        }.sorted { $0.name < $1.name }
        let namedWeeklyQuotas = separateScopes.compactMap { key, scope -> NamedQuota? in
            guard let window = freshWindow(scope.info.weeklyWindow) else { return nil }
            return NamedQuota(
                name: Self.quotaName(for: scope.info, key: key),
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt
            )
        }.sorted { $0.name < $1.name }

        // Session tokens: sum every rollout STARTED inside the official window;
        // long-lived rollouts that began earlier are excluded (documented
        // undercount — the authoritative number is the percentage anyway).
        var sessionTokens = latest?.totals ?? .zero
        if let window = sessionWindow, let resets = window.resetsAt, let minutes = window.windowMinutes {
            let windowStart = resets.addingTimeInterval(-Double(minutes) * 60)
            let inWindow = perFile.filter { $0.start >= windowStart }
            sessionTokens = inWindow.reduce(TokenUsage.zero) { $0 + $1.info.totals }
        }
        let session = SessionUsage(
            tokens: sessionTokens,
            cost: CostEstimate(amountUSD: PricingTable.costUSD(model: defaultModel, usage: sessionTokens) ?? 0),
            // On plans with no official 5h window (session % unavailable),
            // this is the closest honest equivalent to Claude's "current
            // window": when the active rollout itself began — so the UI can
            // show "started 35m ago" instead of silently having nothing.
            startedAt: sessionWindow == nil ? latestEntry?.start : nil,
            resetsAt: sessionWindow?.resetsAt,
            usedPercent: sessionWindow?.usedPercent,
            namedQuotas: namedSessionQuotas.isEmpty ? nil : namedSessionQuotas,
            usedPercentIsFromQuota: sessionWindow != nil
        )

        // Weekly tokens/cost: sum of each rollout's final totals in the window.
        let weekCutoff = now.addingTimeInterval(-7 * 24 * 3600)
        var weekTokens = TokenUsage.zero
        var byDay: [Date: (tokens: Int, cost: Double)] = [:]
        var byHour: [Date: Int] = [:]
        var byModel: [String: TokenUsage] = [:]
        for entry in perFile {
            let info = entry.info
            guard entry.start >= weekCutoff else { continue }
            weekTokens += info.totals
            // nil (model not in PricingTable) excludes the day from the estimate
            // rather than counting it as a verified $0.
            let cost = PricingTable.costUSD(model: defaultModel, usage: info.totals) ?? 0
            let day = entry.start.flooredToDay
            let current = byDay[day] ?? (0, 0)
            byDay[day] = (current.tokens + info.totals.total, current.cost + cost)
            byHour[entry.start.flooredToHour, default: 0] += info.totals.total
            byModel[info.model ?? "unknown", default: .zero] += info.totals
        }
        let breakdown = byModel
            .map { model, tokens in
                ModelUsage(
                    model: model,
                    tokens: tokens.total,
                    // Unknown aliases (router combos, or "unknown" itself) are
                    // never invented — excluded from the estimate, not $0.
                    costUSD: PricingTable.costUSD(model: model, usage: tokens) ?? 0
                )
            }
            .sorted { $0.tokens > $1.tokens }
        let weekly = WeeklyUsage(
            tokens: weekTokens,
            cost: CostEstimate(amountUSD: PricingTable.costUSD(model: defaultModel, usage: weekTokens) ?? 0),
            usedPercent: weeklyWindow?.usedPercent,
            resetsAt: weeklyWindow?.resetsAt,
            dailyTotals: byDay
                .map { DailyTotal(day: $0.key, tokens: $0.value.tokens, costUSD: $0.value.cost) }
                .sorted { $0.day < $1.day },
            hourlyTotals: byHour
                .map { HourlyTotal(hour: $0.key, tokens: $0.value) }
                .sorted { $0.hour < $1.hour },
            namedQuotas: namedWeeklyQuotas.isEmpty ? nil : namedWeeklyQuotas
        )

        let note = [sharedInfo?.planType.map { "Plan: \($0)" }]
            .compactMap(\.self)
            .joined(separator: " · ")

        return UsageSnapshot(
            provider: id,
            capturedAt: now,
            health: failedFiles > 0 ? .degraded : .ok,
            session: session,
            weekly: weekly,
            activeModel: latest?.model ?? defaultModel,
            lastActivityAt: latest?.timestamp,
            note: note.isEmpty ? nil : note,
            modelBreakdown: breakdown.isEmpty ? nil : breakdown,
            rateLimitResetCredits: sharedInfo?.resetCredits
        )
    }

    /// One OpenAI quota pool plus when it was last observed locally.
    struct QuotaScope: Sendable {
        var info: CodexTokenInfo
        var observedAt: Date
    }

    static func quotaKey(for info: CodexTokenInfo) -> String {
        if let limitID = info.limitID, !limitID.isEmpty { return limitID }
        if let limitName = info.limitName, !limitName.isEmpty { return "named:\(limitName)" }
        return sharedLimitID
    }

    static func quotaName(for info: CodexTokenInfo, key: String) -> String {
        info.limitName ?? key.replacingOccurrences(of: "named:", with: "")
    }

    /// Keeps the freshest official observation for each OpenAI quota pool.
    static func freshestQuotaScopesByLimitID(
        _ perFile: [(info: CodexTokenInfo, start: Date)]
    ) -> [String: QuotaScope] {
        var byLimitID: [String: QuotaScope] = [:]
        for entry in perFile {
            let key = quotaKey(for: entry.info)
            let observedAt = entry.info.timestamp ?? entry.start
            if observedAt > (byLimitID[key]?.observedAt ?? .distantPast) {
                byLimitID[key] = QuotaScope(info: entry.info, observedAt: observedAt)
            }
        }
        return byLimitID
    }
}
