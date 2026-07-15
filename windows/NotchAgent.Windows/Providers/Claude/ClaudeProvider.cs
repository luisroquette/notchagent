using NotchAgent.Windows.Models;
using NotchAgent.Windows.Providers.Shared;
using NotchAgent.Windows.Services;

namespace NotchAgent.Windows.Providers.Claude;

/// Claude Code usage from two complementary sources:
/// 1. Local transcripts — tokens, cost estimates, 5h session blocks, hourly
///    activity. Always available. Scans both the CLI's own transcripts and
///    (when present) the Desktop app's agent-mode sessions.
/// 2. Optional API probe — authoritative 5h/7d quota percentages, reset
///    times and limit status from response headers.
public sealed class ClaudeProvider : IUsageProvider
{
    public ProviderId Id => ProviderId.ClaudeCode;

    private readonly List<string> _roots;
    private readonly ClaudeScanCache _cache = new();
    private readonly ClaudeQuotaProbe? _probe;
    private static readonly TimeSpan Lookback = TimeSpan.FromDays(8);
    private static readonly TimeSpan BlockLength = TimeSpan.FromHours(5);

    public ClaudeProvider(IEnumerable<string>? roots = null, ClaudeQuotaProbe? probe = null)
    {
        _roots = roots?.ToList() ?? DefaultRoots();
        _probe = probe ?? new ClaudeQuotaProbe();
    }

    private static List<string> DefaultRoots() => new()
    {
        Path.Combine(AppPaths.Home, ".claude", "projects"),
    };

    public ProviderInstallation DetectInstallation()
    {
        foreach (var root in _roots)
        {
            if (Directory.Exists(root)) return ProviderInstallation.Installed(root);
        }
        return ProviderInstallation.NotInstalled;
    }

    public async Task<UsageSnapshot> FetchSnapshotAsync(AppSettings settings, CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        if (DetectInstallation().Kind != ProviderInstallationKind.Installed)
        {
            return new UsageSnapshot { Provider = Id, Health = ProviderHealth.NotInstalled };
        }

        // Freshness rules: a cached quota is only trusted while it is recent
        // AND its windows have not already reset — an expired token or dead
        // network must never freeze yesterday's 60% as today's truth.
        ClaudeQuota? quota = null;
        if (settings.ClaudeQuotaProbeEnabled && _probe is not null)
        {
            quota = await _probe.CurrentQuotaAsync(ct);
            if (quota is { FetchedAt: var fetched } && now - fetched > TimeSpan.FromMinutes(15))
            {
                quota = null;
            }
        }
        var freshSessionReset = quota?.SessionResetsAt is { } sr && sr > now ? sr : (DateTimeOffset?)null;
        var freshWeeklyReset = quota?.WeeklyResetsAt is { } wr && wr > now ? wr : (DateTimeOffset?)null;

        var files = _roots.SelectMany(r => FileScan.RecentFiles(r, "jsonl", now - Lookback)).ToList();
        var merged = new Dictionary<DateTimeOffset, ClaudeFileStat.HourStat>();
        var mergedModels = new Dictionary<string, ClaudeFileStat.ModelStat>();
        DateTimeOffset? lastActivity = null;
        string? lastModel = null;
        int failedFiles = 0;

        foreach (var url in files)
        {
            ClaudeFileStat? stat;
            try
            {
                stat = _cache.Stat(url);
            }
            catch (IOException ex)
            {
                failedFiles++;
                Log.Providers.LogError("claude: failed to parse {0}: {1}", Path.GetFileName(url), ex.Message);
                continue;
            }
            if (stat is null) continue;

            foreach (var (hour, bucket) in stat.Hours)
            {
                if (!merged.TryGetValue(hour, out var existing))
                {
                    existing = new ClaudeFileStat.HourStat();
                    merged[hour] = existing;
                }
                existing.Tokens += bucket.Tokens;
                existing.CostUsd += bucket.CostUsd;
                existing.Messages += bucket.Messages;
            }
            foreach (var (model, modelStat) in stat.ByModel)
            {
                if (!mergedModels.TryGetValue(model, out var existing))
                {
                    existing = new ClaudeFileStat.ModelStat();
                    mergedModels[model] = existing;
                }
                existing.Tokens += modelStat.Tokens;
                existing.CostUsd += modelStat.CostUsd;
            }
            if (stat.LastActivity is { } activity && (lastActivity is null || activity > lastActivity))
            {
                lastActivity = activity;
                lastModel = stat.LastModel;
            }
        }

        var scannedPaths = files.ToHashSet();
        _cache.Prune(scannedPaths);

        if (merged.Count == 0 && quota is null)
        {
            var health = failedFiles > 0 ? ProviderHealth.ParseError : ProviderHealth.NoData;
            return new UsageSnapshot
            {
                Provider = Id,
                Health = health,
                Note = files.Count == 0 ? "No activity in the last 8 days" : null,
            };
        }

        // Session window: the API reset time is authoritative (start = reset
        // − 5h, matching what the % refers to); the local block heuristic is
        // fallback.
        SessionUsage? session = null;
        (DateTimeOffset Start, DateTimeOffset End)? sessionWindow =
            freshSessionReset is { } fsr ? (fsr - BlockLength, fsr) : CurrentBlock(merged.Keys, now);
        if (sessionWindow is { } window)
        {
            var (tokens, cost) = SumBuckets(merged, window.Start, window.End);
            double? usedPercent = freshSessionReset is not null ? quota?.SessionPercent : null;
            usedPercent ??= settings.ClaudeSessionTokenBudget is { } budget
                ? Math.Min(100, (double)tokens.Total / Math.Max(budget, 1) * 100)
                : null;
            session = new SessionUsage
            {
                Tokens = tokens,
                Cost = new CostEstimate { AmountUsd = cost },
                StartedAt = window.Start,
                ResetsAt = window.End,
                UsedPercent = usedPercent,
            };
        }

        // Weekly window aligned to the API reset when known.
        var weekCutoff = freshWeeklyReset is { } fwr ? fwr - TimeSpan.FromDays(7) : now - TimeSpan.FromDays(7);
        var weekTokens = new TokenUsage();
        double weekCost = 0;
        var byDay = new Dictionary<DateTimeOffset, (long Tokens, double Cost)>();
        var hourly = new List<HourlyTotal>();
        foreach (var (hour, bucket) in merged)
        {
            if (hour < weekCutoff) continue;
            weekTokens += bucket.Tokens;
            weekCost += bucket.CostUsd;
            var day = new DateTimeOffset(hour.Date, TimeSpan.Zero);
            var current = byDay.GetValueOrDefault(day, (0, 0));
            byDay[day] = (current.Tokens + bucket.Tokens.Total, current.Cost + bucket.CostUsd);
            hourly.Add(new HourlyTotal { Hour = hour, Tokens = bucket.Tokens.Total });
        }

        double? weeklyPercent = freshWeeklyReset is not null ? quota?.WeeklyPercent : null;
        weeklyPercent ??= settings.ClaudeWeeklyTokenBudget is { } weekBudget
            ? Math.Min(100, (double)weekTokens.Total / Math.Max(weekBudget, 1) * 100)
            : null;

        var weekly = new WeeklyUsage
        {
            Tokens = weekTokens,
            Cost = new CostEstimate { AmountUsd = weekCost },
            UsedPercent = weeklyPercent,
            ResetsAt = freshWeeklyReset,
            DailyTotals = byDay.Select(kv => new DailyTotal { Day = kv.Key, Tokens = kv.Value.Tokens, CostUsd = kv.Value.Cost })
                .OrderBy(d => d.Day).ToList(),
            HourlyTotals = hourly.OrderBy(h => h.Hour).ToList(),
        };

        var breakdown = mergedModels
            .Select(kv => new ModelUsage { Model = kv.Key, Tokens = kv.Value.Tokens.Total, CostUsd = kv.Value.CostUsd })
            .OrderByDescending(m => m.CostUsd)
            .ToList();

        var quotaStatus = (freshSessionReset is not null || freshWeeklyReset is not null)
            ? quota?.Status switch
            {
                ClaudeQuotaStatus.Ok => Models.QuotaStatus.Ok,
                ClaudeQuotaStatus.Warning => Models.QuotaStatus.Warning,
                ClaudeQuotaStatus.Blocked => Models.QuotaStatus.Blocked,
                _ => (Models.QuotaStatus?)null,
            }
            : null;

        return new UsageSnapshot
        {
            Provider = Id,
            CapturedAt = now,
            Health = failedFiles > 0 ? ProviderHealth.Degraded : ProviderHealth.Ok,
            Session = session,
            Weekly = weekly,
            ActiveModel = lastModel,
            LastActivityAt = lastActivity,
            Note = LimitingNote(quota),
            QuotaStatus = quotaStatus,
            ModelBreakdown = breakdown.Count > 0 ? breakdown : null,
        };
    }

    /// Claude Plans meter usage in rolling ~5h session blocks: a block starts
    /// at the floored hour of the first activity after the previous block
    /// ended, and lasts 5 hours.
    private static (DateTimeOffset Start, DateTimeOffset End)? CurrentBlock(IEnumerable<DateTimeOffset> activityHours, DateTimeOffset now)
    {
        DateTimeOffset? blockStart = null;
        var blockEnd = DateTimeOffset.MinValue;
        foreach (var hour in activityHours.OrderBy(h => h))
        {
            if (blockStart is null || hour >= blockEnd)
            {
                blockStart = hour;
                blockEnd = hour + BlockLength;
            }
        }
        if (blockStart is not { } start || now < start || now >= blockEnd) return null;
        return (start, blockEnd);
    }

    /// Hour buckets are the finest grain we keep, so window boundaries carry
    /// up to ±1 bucket of imprecision — documented in the README.
    private static (TokenUsage Tokens, double CostUsd) SumBuckets(
        Dictionary<DateTimeOffset, ClaudeFileStat.HourStat> merged, DateTimeOffset start, DateTimeOffset end)
    {
        var tokens = new TokenUsage();
        double cost = 0;
        var flooredStart = ClaudeTranscriptParser.FlooredToHour(start);
        foreach (var (hour, bucket) in merged)
        {
            if (hour >= flooredStart && hour < end)
            {
                tokens += bucket.Tokens;
                cost += bucket.CostUsd;
            }
        }
        return (tokens, cost);
    }

    private static string? LimitingNote(ClaudeQuota? quota) => quota?.LimitingWindow switch
    {
        "five_hour" => "Limiting window: 5h session",
        "seven_day" => "Limiting window: 7-day",
        _ => null,
    };
}
