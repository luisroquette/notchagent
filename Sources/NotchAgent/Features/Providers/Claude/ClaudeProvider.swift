import Foundation

/// Claude Code usage from two complementary sources:
/// 1. Local transcripts (`~/.claude/projects/**/*.jsonl`) — tokens, cost
///    estimates, 5h session blocks, hourly activity. Always available.
/// 2. Optional API probe (`ClaudeQuotaProbe`) — authoritative 5h/7d quota
///    percentages, reset times and limit status from response headers.
/// When the probe is disabled or no OAuth token exists, percentages fall back
/// to user-configured budgets (or stay hidden — never fabricated).
struct ClaudeProvider: UsageProvider {
    let id = ProviderID.claudeCode
    let capabilities: ProviderCapabilities = [
        .sessionTokens, .sessionPercent, .weeklyTokens, .weeklyPercent, .costEstimate, .resetSchedule,
    ]

    private let roots: [URL]
    private let cache = ClaudeScanCache()
    private let probe: ClaudeQuotaProbe?
    private static let lookback: TimeInterval = 8 * 24 * 3600

    /// Every place Claude Code writes transcripts on this Mac: the CLI and
    /// the Desktop app's agent mode (same JSONL format, different root).
    static let defaultRoots: [URL] = [
        AppPaths.home.appendingPathComponent(".claude/projects"),
        AppPaths.home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions"),
    ]

    init(roots: [URL] = ClaudeProvider.defaultRoots, probe: ClaudeQuotaProbe? = ClaudeQuotaProbe()) {
        self.roots = roots
        self.probe = probe
    }

    init(root: URL, probe: ClaudeQuotaProbe?) {
        self.init(roots: [root], probe: probe)
    }

    func detectInstallation() -> ProviderInstallation {
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            return .installed(dataPath: root.path)
        }
        return .notInstalled
    }

    func fetchSnapshot(settings: AppSettings) async throws -> UsageSnapshot {
        let now = Date()
        guard case .installed = detectInstallation() else {
            return UsageSnapshot(provider: id, health: .notInstalled)
        }

        // Freshness rules (review finding): a cached quota is only trusted
        // while it is recent AND its windows have not already reset — an
        // expired token or dead network must never freeze yesterday's 60%
        // as today's truth. Stale quota degrades to the local heuristics.
        var quota: ClaudeQuota?
        if settings.claudeQuotaProbeEnabled, let probe {
            quota = await probe.currentQuota()
            if let fetched = quota?.fetchedAt, now.timeIntervalSince(fetched) > 15 * 60 {
                quota = nil
            }
        }
        let freshSessionReset = quota?.sessionResetsAt.flatMap { $0 > now ? $0 : nil }
        let freshWeeklyReset = quota?.weeklyResetsAt.flatMap { $0 > now ? $0 : nil }

        let files = roots.flatMap {
            recentFiles(under: $0, ext: "jsonl", modifiedAfter: now.addingTimeInterval(-Self.lookback))
        }
        var merged: [Date: ClaudeFileStat.HourStat] = [:]
        var mergedModels: [String: ClaudeFileStat.ModelStat] = [:]
        var lastActivity: Date?
        var lastModel: String?
        var failedFiles = 0

        for url in files {
            let stat: ClaudeFileStat?
            do {
                stat = try await cache.stat(for: url)
            } catch {
                failedFiles += 1
                Log.providers.error("claude: failed to parse \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
            guard let stat else { continue }

            for (hour, bucket) in stat.hours {
                var existing = merged[hour] ?? .init()
                existing.tokens += bucket.tokens
                existing.costUSD += bucket.costUSD
                existing.messages += bucket.messages
                merged[hour] = existing
            }
            for (model, modelStat) in stat.byModel {
                var existing = mergedModels[model] ?? .init()
                existing.tokens += modelStat.tokens
                existing.costUSD += modelStat.costUSD
                mergedModels[model] = existing
            }
            if let activity = stat.lastActivity, lastActivity.map({ activity > $0 }) ?? true {
                lastActivity = activity
                lastModel = stat.lastModel
            }
        }

        guard !merged.isEmpty || quota != nil else {
            let health: ProviderHealth = failedFiles > 0 ? .parseError : .noData
            return UsageSnapshot(provider: id, health: health, note: files.isEmpty ? "No activity in the last 8 days" : nil)
        }

        // Session window: the API reset time is authoritative (start = reset − 5h,
        // matching what the % refers to); the local block heuristic is fallback.
        var session: SessionUsage?
        let sessionWindow: (start: Date, end: Date)? =
            freshSessionReset.map { ($0.addingTimeInterval(-SessionBlocks.blockLength), $0) }
            ?? SessionBlocks.currentBlock(activityHours: Array(merged.keys), now: now)
        if let window = sessionWindow {
            let (tokens, cost) = Self.sumBuckets(merged, from: window.start, to: window.end)
            session = SessionUsage(
                tokens: tokens,
                cost: CostEstimate(amountUSD: cost),
                startedAt: window.start,
                resetsAt: window.end,
                usedPercent: (freshSessionReset != nil ? quota?.sessionPercent : nil)
                    ?? settings.claudeSessionTokenBudget.map { budget in
                        min(100, Double(tokens.total) / Double(max(budget, 1)) * 100)
                    }
            )
        }

        // Weekly window aligned to the API reset when known (tokens must refer
        // to the same window as the percentage beside them).
        let weekCutoff = freshWeeklyReset.map { $0.addingTimeInterval(-7 * 24 * 3600) }
            ?? now.addingTimeInterval(-7 * 24 * 3600)
        var weekTokens = TokenUsage.zero
        var weekCost = 0.0
        var byDay: [Date: (tokens: Int, cost: Double)] = [:]
        var hourly: [HourlyTotal] = []
        for (hour, bucket) in merged where hour >= weekCutoff {
            weekTokens += bucket.tokens
            weekCost += bucket.costUSD
            let day = hour.flooredToDay
            let current = byDay[day] ?? (0, 0)
            byDay[day] = (current.tokens + bucket.tokens.total, current.cost + bucket.costUSD)
            hourly.append(HourlyTotal(hour: hour, tokens: bucket.tokens.total))
        }
        let weekly = WeeklyUsage(
            tokens: weekTokens,
            cost: CostEstimate(amountUSD: weekCost),
            usedPercent: (freshWeeklyReset != nil ? quota?.weeklyPercent : nil)
                ?? settings.claudeWeeklyTokenBudget.map { budget in
                    min(100, Double(weekTokens.total) / Double(max(budget, 1)) * 100)
                },
            resetsAt: freshWeeklyReset,
            dailyTotals: byDay
                .map { DailyTotal(day: $0.key, tokens: $0.value.tokens, costUSD: $0.value.cost) }
                .sorted { $0.day < $1.day },
            hourlyTotals: hourly.sorted { $0.hour < $1.hour }
        )

        let breakdown = mergedModels
            .map { ModelUsage(model: $0.key, tokens: $0.value.tokens.total, costUSD: $0.value.costUSD) }
            .sorted { $0.costUSD > $1.costUSD }

        var modelHealth: [ModelHealth]?
        if settings.claudeQuotaProbeEnabled, let probe {
            let recorded = await probe.modelHealthSnapshot()
            modelHealth = recorded.isEmpty ? nil : recorded
        }

        // Evict cache entries for files that left the lookback window —
        // without this, seenKeys of every transcript ever seen stay resident.
        await cache.prune(keeping: Set(files.map(\.path)))

        return UsageSnapshot(
            provider: id,
            capturedAt: now,
            health: failedFiles > 0 ? .degraded : .ok,
            session: session,
            weekly: weekly,
            activeModel: lastModel,
            lastActivityAt: lastActivity,
            note: limitingNote(quota),
            quotaStatus: freshSessionReset != nil || freshWeeklyReset != nil ? quota?.status : nil,
            modelBreakdown: breakdown.isEmpty ? nil : breakdown,
            modelHealth: modelHealth
        )
    }

    /// Hour buckets are the finest grain we keep, so window boundaries carry
    /// up to ±1 bucket of imprecision — documented in the README.
    static func sumBuckets(
        _ merged: [Date: ClaudeFileStat.HourStat],
        from start: Date,
        to end: Date
    ) -> (tokens: TokenUsage, costUSD: Double) {
        var tokens = TokenUsage.zero
        var cost = 0.0
        let flooredStart = start.flooredToHour
        for (hour, bucket) in merged where hour >= flooredStart && hour < end {
            tokens += bucket.tokens
            cost += bucket.costUSD
        }
        return (tokens, cost)
    }

    private func limitingNote(_ quota: ClaudeQuota?) -> String? {
        switch quota?.limitingWindow {
        case "five_hour": "Limiting window: 5h session"
        case "seven_day": "Limiting window: 7-day"
        default: nil
        }
    }
}
