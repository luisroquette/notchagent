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
        guard case .installed = detectInstallation() else {
            return UsageSnapshot(provider: id, health: .notInstalled)
        }

        let files = recentFiles(under: root, ext: "jsonl", modifiedAfter: now.addingTimeInterval(-Self.lookback))
        guard !files.isEmpty else {
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

        guard !perFile.isEmpty else {
            return UsageSnapshot(provider: id, health: failedFiles > 0 ? .parseError : .noData)
        }

        // Newest rollout carries the freshest rate limits + current session totals.
        let latest = perFile.max { ($0.info.timestamp ?? .distantPast) < ($1.info.timestamp ?? .distantPast) }!.info
        // Window semantics vary per plan — classify by duration, never by
        // position — and NEVER trust a window whose reset already passed
        // (an idle weekend must not freeze Friday's 80% as today's truth).
        func freshWindow(_ window: CodexRateWindow?) -> CodexRateWindow? {
            guard let window else { return nil }
            if let resets = window.resetsAt, resets <= now { return nil }
            return window
        }
        let sessionWindow = freshWindow(latest.sessionWindow)
        let weeklyWindow = freshWindow(latest.weeklyWindow)

        // Session tokens: sum every rollout STARTED inside the official window;
        // long-lived rollouts that began earlier are excluded (documented
        // undercount — the authoritative number is the percentage anyway).
        var sessionTokens = latest.totals
        if let window = sessionWindow, let resets = window.resetsAt, let minutes = window.windowMinutes {
            let windowStart = resets.addingTimeInterval(-Double(minutes) * 60)
            let inWindow = perFile.filter { $0.start >= windowStart }
            sessionTokens = inWindow.reduce(TokenUsage.zero) { $0 + $1.info.totals }
        }
        let session = SessionUsage(
            tokens: sessionTokens,
            cost: CostEstimate(amountUSD: PricingTable.costUSD(model: defaultModel, usage: sessionTokens)),
            resetsAt: sessionWindow?.resetsAt,
            usedPercent: sessionWindow?.usedPercent
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
            let cost = PricingTable.costUSD(model: defaultModel, usage: info.totals)
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
