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
        let latestEntry = perFile.max { ($0.info.timestamp ?? .distantPast) < ($1.info.timestamp ?? .distantPast) }!
        let latest = latestEntry.info
        // Window semantics vary per plan — classify by duration, never by
        // position — and NEVER trust a window whose reset already passed
        // (an idle weekend must not freeze Friday's 80% as today's truth).
        func freshWindow(_ window: CodexRateWindow?) -> CodexRateWindow? {
            guard let window else { return nil }
            if let resets = window.resetsAt, resets <= now { return nil }
            return window
        }
        let sessionWindow = freshWindow(latest.sessionWindow)

        // A single rate-limits response only ever reports ONE weekly scope at
        // a time — verified against live data: `limit_name` is null on every
        // locally-observed event, for BOTH concurrent scopes, so it cannot
        // distinguish them (an earlier version of this fix wrongly assumed
        // it could — see commit history). The only field that actually
        // differs between two concurrent weekly windows is `resetsAt`, so
        // that's the key. A session using only one model may never once
        // report the other scope, so recovering every known scope means
        // keeping the freshest sighting of each across every
        // recently-scanned rollout, not just the single newest file.
        let weeklyScopes = Self.freshestWeeklyScopes(perFile)
        // Codex exposes no reliable local label for "this is the account-wide
        // total" vs. "this is one model's own cap" — so instead of guessing
        // which scope is the aggregate, the headline number is always
        // whichever known scope has the LEAST headroom. That's the one that
        // actually blocks the user next, regardless of what it's called
        // (matches how a blocked quotaStatus already forces the gauge to
        // empty elsewhere — worst case always wins, never a calm number that
        // hides a real limit).
        let primaryWeeklyScope = weeklyScopes.values.max { $0.window.usedPercent < $1.window.usedPercent }
        let weeklyWindow = freshWindow(primaryWeeklyScope?.window)
        // Best-effort label from the model active when this scope was last
        // observed (real data, never invented) — falls back to the reset
        // date when no model is known for that sighting.
        let namedWeeklyQuotas: [NamedQuota] = weeklyScopes.values
            .map { scope in
                NamedQuota(
                    name: scope.model ?? "Weekly cap · resets \(scope.window.resetsAt.map { Format.time($0) } ?? "?")",
                    usedPercent: scope.window.usedPercent,
                    resetsAt: scope.window.resetsAt
                )
            }
            .sorted { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }

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
            cost: CostEstimate(amountUSD: PricingTable.costUSD(model: defaultModel, usage: sessionTokens) ?? 0),
            // On plans with no official 5h window (session % unavailable),
            // this is the closest honest equivalent to Claude's "current
            // window": when the active rollout itself began — so the UI can
            // show "started 35m ago" instead of silently having nothing.
            startedAt: sessionWindow == nil ? latestEntry.start : nil,
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

    /// One weekly scope's window plus when it was last observed locally and
    /// which model (if any) was active for that sighting.
    struct WeeklyScope: Sendable, Equatable {
        var window: CodexRateWindow
        var observedAt: Date
        var model: String?
    }

    /// Recovers every distinct weekly scope seen across recently-scanned
    /// rollouts, keyed by `resetsAt` — the only field that reliably
    /// distinguishes two concurrent weekly windows in local data (`limitName`
    /// is null on every locally-observed rate-limits event and cannot be
    /// used for this). Pure and testable: a single API response only reports
    /// one scope per turn, so this keeps the freshest sighting of each
    /// rather than assuming the single newest event covers every scope.
    static func freshestWeeklyScopes(
        _ perFile: [(info: CodexTokenInfo, start: Date)]
    ) -> [TimeInterval: WeeklyScope] {
        var byScope: [TimeInterval: WeeklyScope] = [:]
        for entry in perFile {
            guard let window = entry.info.weeklyWindow, let resets = window.resetsAt else { continue }
            let key = resets.timeIntervalSince1970
            let observedAt = entry.info.timestamp ?? entry.start
            if observedAt > (byScope[key]?.observedAt ?? .distantPast) {
                byScope[key] = WeeklyScope(window: window, observedAt: observedAt, model: entry.info.model)
            }
        }
        return byScope
    }
}
