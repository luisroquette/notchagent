import Foundation

/// Codex is the only provider with authoritative local quota data: rollout files
/// embed `used_percent` for the 5h and weekly windows plus reset timestamps.
/// Session tokens describe the newest rollout; percentages are account-wide.
struct CodexProvider: UsageProvider {
    let id = ProviderID.codex
    let capabilities: ProviderCapabilities = [
        .sessionTokens, .sessionPercent, .weeklyTokens, .weeklyPercent, .costEstimate, .resetSchedule,
    ]

    private let root: URL
    private let defaultModel = "gpt-5"
    private let cache = FileScanCache<CodexTokenInfo?>()
    private static let lookback: TimeInterval = 8 * 24 * 3600

    init(root: URL = AppPaths.home.appendingPathComponent(".codex/sessions")) {
        self.root = root
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

        let files = recentFiles(under: root, ext: "jsonl", modifiedAfter: now.addingTimeInterval(-Self.lookback))
        guard !files.isEmpty else {
            return UsageSnapshot(provider: id, health: .noData, note: "No sessions in the last 8 days")
        }

        var perFile: [CodexTokenInfo] = []
        var failedFiles = 0
        for url in files {
            do {
                if let info = try await cache.value(for: url, parse: { try CodexRolloutParser.latestTokenInfo(at: $0) }),
                   let info {
                    perFile.append(info)
                }
            } catch {
                failedFiles += 1
                Log.providers.error("codex: failed to parse \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !perFile.isEmpty else {
            return UsageSnapshot(provider: id, health: failedFiles > 0 ? .parseError : .noData)
        }

        // Newest rollout carries the freshest rate limits + current session totals.
        let latest = perFile.max { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }!
        // Window semantics vary per plan — classify by duration, never by position.
        let sessionWindow = latest.sessionWindow
        let weeklyWindow = latest.weeklyWindow

        let session = SessionUsage(
            tokens: latest.totals,
            cost: CostEstimate(amountUSD: PricingTable.costUSD(model: defaultModel, usage: latest.totals)),
            resetsAt: sessionWindow?.resetsAt,
            usedPercent: sessionWindow?.usedPercent
        )

        // Weekly tokens/cost: sum of each rollout's final totals in the window.
        let weekCutoff = now.addingTimeInterval(-7 * 24 * 3600)
        var weekTokens = TokenUsage.zero
        var byDay: [Date: (tokens: Int, cost: Double)] = [:]
        var byHour: [Date: Int] = [:]
        var byModel: [String: TokenUsage] = [:]
        for info in perFile {
            guard let ts = info.timestamp, ts >= weekCutoff else { continue }
            weekTokens += info.totals
            let cost = PricingTable.costUSD(model: defaultModel, usage: info.totals)
            let day = ts.flooredToDay
            let current = byDay[day] ?? (0, 0)
            byDay[day] = (current.tokens + info.totals.total, current.cost + cost)
            byHour[ts.flooredToHour, default: 0] += info.totals.total
            byModel[info.model ?? "unknown", default: .zero] += info.totals
        }
        let breakdown = byModel
            .map { model, tokens in
                ModelUsage(
                    model: model,
                    tokens: tokens.total,
                    // Unknown aliases (router combos) price at 0 — never invented.
                    costUSD: PricingTable.costUSD(model: model, usage: tokens)
                )
            }
            .sorted { $0.tokens > $1.tokens }
        let weekly = WeeklyUsage(
            tokens: weekTokens,
            cost: CostEstimate(amountUSD: PricingTable.costUSD(model: defaultModel, usage: weekTokens)),
            usedPercent: weeklyWindow?.usedPercent,
            resetsAt: weeklyWindow?.resetsAt,
            dailyTotals: byDay
                .map { DailyTotal(day: $0.key, tokens: $0.value.tokens, costUSD: $0.value.cost) }
                .sorted { $0.day < $1.day },
            hourlyTotals: byHour
                .map { HourlyTotal(hour: $0.key, tokens: $0.value) }
                .sorted { $0.hour < $1.hour }
        )

        let note = [latest.limitName, latest.planType.map { "Plan: \($0)" }]
            .compactMap(\.self)
            .joined(separator: " · ")

        return UsageSnapshot(
            provider: id,
            capturedAt: now,
            health: failedFiles > 0 ? .degraded : .ok,
            session: session,
            weekly: weekly,
            activeModel: latest.model ?? defaultModel,
            lastActivityAt: latest.timestamp,
            note: note.isEmpty ? nil : note,
            modelBreakdown: breakdown.isEmpty ? nil : breakdown
        )
    }
}
