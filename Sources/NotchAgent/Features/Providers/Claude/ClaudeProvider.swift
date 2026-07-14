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

    private let root: URL
    private let cache = ClaudeScanCache()
    private let probe: ClaudeQuotaProbe?
    private static let lookback: TimeInterval = 8 * 24 * 3600

    init(
        root: URL = AppPaths.home.appendingPathComponent(".claude/projects"),
        probe: ClaudeQuotaProbe? = ClaudeQuotaProbe()
    ) {
        self.root = root
        self.probe = probe
    }

    func detectInstallation() -> ProviderInstallation {
        FileManager.default.fileExists(atPath: root.path)
            ? .installed(dataPath: root.path)
            : .notInstalled
    }

    func fetchSnapshot(settings: AppSettings) async throws -> UsageSnapshot {
        let now = Date()
        guard case .installed = detectInstallation() else {
            return UsageSnapshot(provider: id, health: .notInstalled)
        }

        var quota: ClaudeQuota?
        if settings.claudeQuotaProbeEnabled, let probe {
            quota = await probe.currentQuota()
        }

        let files = recentFiles(under: root, ext: "jsonl", modifiedAfter: now.addingTimeInterval(-Self.lookback))
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

        // Session = current 5h block from transcripts; percent/reset prefer the API.
        var session: SessionUsage?
        if let block = SessionBlocks.currentBlock(activityHours: Array(merged.keys), now: now) {
            var tokens = TokenUsage.zero
            var cost = 0.0
            for (hour, bucket) in merged where hour >= block.start && hour < block.end {
                tokens += bucket.tokens
                cost += bucket.costUSD
            }
            session = SessionUsage(
                tokens: tokens,
                cost: CostEstimate(amountUSD: cost),
                startedAt: block.start,
                resetsAt: quota?.sessionResetsAt ?? block.end,
                usedPercent: quota?.sessionPercent ?? settings.claudeSessionTokenBudget.map { budget in
                    min(100, Double(tokens.total) / Double(max(budget, 1)) * 100)
                }
            )
        } else if let quota, let percent = quota.sessionPercent {
            // Idle locally but the account window still carries usage.
            session = SessionUsage(resetsAt: quota.sessionResetsAt, usedPercent: percent)
        }

        // Weekly = trailing 7 days of transcripts; percent/reset prefer the API.
        let weekCutoff = now.addingTimeInterval(-7 * 24 * 3600)
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
            usedPercent: quota?.weeklyPercent ?? settings.claudeWeeklyTokenBudget.map { budget in
                min(100, Double(weekTokens.total) / Double(max(budget, 1)) * 100)
            },
            resetsAt: quota?.weeklyResetsAt,
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

        return UsageSnapshot(
            provider: id,
            capturedAt: now,
            health: failedFiles > 0 ? .degraded : .ok,
            session: session,
            weekly: weekly,
            activeModel: lastModel,
            lastActivityAt: lastActivity,
            note: limitingNote(quota),
            quotaStatus: quota?.status,
            modelBreakdown: breakdown.isEmpty ? nil : breakdown,
            modelHealth: modelHealth
        )
    }

    private func limitingNote(_ quota: ClaudeQuota?) -> String? {
        switch quota?.limitingWindow {
        case "five_hour": "Limiting window: 5h session"
        case "seven_day": "Limiting window: 7-day"
        default: nil
        }
    }
}
