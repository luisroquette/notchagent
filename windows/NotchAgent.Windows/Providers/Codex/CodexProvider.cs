using System.Globalization;
using System.Text.RegularExpressions;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Providers.Shared;
using NotchAgent.Windows.Services;

namespace NotchAgent.Windows.Providers.Codex;

/// Codex is the only provider with authoritative local quota data on some
/// plans: rollout files embed `used_percent` for the 5h and weekly windows
/// plus reset timestamps. On weekly-only plans (no session %), the current
/// active rollout's start time is exposed instead — the closest honest
/// equivalent to Claude's "current window".
public sealed class CodexProvider : IUsageProvider
{
    public ProviderId Id => ProviderId.Codex;

    private readonly string _root;
    private const string DefaultModel = "gpt-5";
    private readonly Dictionary<string, CodexTokenInfo?> _cache = new();
    private static readonly TimeSpan Lookback = TimeSpan.FromDays(8);
    private static readonly Regex RolloutStamp = new(@"^rollout-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})-", RegexOptions.Compiled);

    public CodexProvider(string? root = null)
    {
        _root = root ?? Path.Combine(AppPaths.Home, ".codex", "sessions");
    }

    /// "rollout-2026-07-13T14-04-44-<uuid>.jsonl" → local start date.
    public static DateTimeOffset? RolloutStart(string path)
    {
        var name = Path.GetFileName(path);
        var match = RolloutStamp.Match(name);
        if (!match.Success) return null;
        var stamp = match.Groups[1].Value; // "2026-07-13T14-04-44"
        return DateTimeOffset.TryParseExact(
            stamp, "yyyy-MM-dd'T'HH-mm-ss", CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeLocal, out var date) ? date : null;
    }

    public ProviderInstallation DetectInstallation() =>
        Directory.Exists(_root) ? ProviderInstallation.Installed(_root) : ProviderInstallation.NotInstalled;

    public Task<UsageSnapshot> FetchSnapshotAsync(AppSettings settings, CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        if (DetectInstallation().Kind != ProviderInstallationKind.Installed)
        {
            return Task.FromResult(new UsageSnapshot { Provider = Id, Health = ProviderHealth.NotInstalled });
        }

        var files = FileScan.RecentFiles(_root, "jsonl", now - Lookback);
        if (files.Count == 0)
        {
            return Task.FromResult(new UsageSnapshot
            {
                Provider = Id,
                Health = ProviderHealth.NoData,
                Note = "No sessions in the last 8 days",
            });
        }

        // Rollout totals are CUMULATIVE for the whole rollout, so window
        // membership must use when the rollout STARTED (from the filename),
        // not its last event — otherwise a 10h-old session whose last ping
        // was 5 minutes ago would dump 10h of tokens into the current 5h window.
        var perFile = new List<(CodexTokenInfo Info, DateTimeOffset Start)>();
        int failedFiles = 0;
        foreach (var path in files)
        {
            try
            {
                if (!_cache.TryGetValue(path, out var info))
                {
                    info = CodexRolloutParser.LatestTokenInfo(path);
                    _cache[path] = info;
                }
                if (info is not null)
                {
                    var start = RolloutStart(path) ?? info.Timestamp ?? DateTimeOffset.MinValue;
                    perFile.Add((info, start));
                }
            }
            catch (IOException ex)
            {
                failedFiles++;
                Log.Providers.LogError("codex: failed to parse {0}: {1}", Path.GetFileName(path), ex.Message);
            }
        }
        var scanned = files.ToHashSet();
        foreach (var key in _cache.Keys.Where(k => !scanned.Contains(k)).ToList()) _cache.Remove(key);

        if (perFile.Count == 0)
        {
            return Task.FromResult(new UsageSnapshot
            {
                Provider = Id,
                Health = failedFiles > 0 ? ProviderHealth.ParseError : ProviderHealth.NoData,
            });
        }

        var latestEntry = perFile.MaxBy(f => f.Info.Timestamp ?? DateTimeOffset.MinValue);
        var latest = latestEntry.Info;

        // Window semantics vary per plan — classify by duration, never by
        // position — and NEVER trust a window whose reset already passed.
        CodexRateWindow? FreshWindow(CodexRateWindow? w) =>
            w is null ? null : (w.ResetsAt is { } r && r <= now ? null : w);
        var sessionWindow = FreshWindow(latest.SessionWindow);
        var weeklyWindow = FreshWindow(latest.WeeklyWindow);

        // Session tokens: sum every rollout STARTED inside the official window.
        var sessionTokens = latest.Totals;
        if (sessionWindow is { ResetsAt: { } resets, WindowMinutes: { } minutes })
        {
            var windowStart = resets - TimeSpan.FromMinutes(minutes);
            sessionTokens = perFile.Where(f => f.Start >= windowStart)
                .Aggregate(new TokenUsage(), (acc, f) => acc + f.Info.Totals);
        }

        var session = new SessionUsage
        {
            Tokens = sessionTokens,
            Cost = new CostEstimate { AmountUsd = PricingTable.CostUsd(DefaultModel, sessionTokens) },
            // On plans with no official 5h window, this is the closest honest
            // equivalent to Claude's "current window": when the active rollout
            // itself began — so the UI can show "started 35m ago".
            StartedAt = sessionWindow is null ? latestEntry.Start : null,
            ResetsAt = sessionWindow?.ResetsAt,
            UsedPercent = sessionWindow?.UsedPercent,
        };

        var weekCutoff = now - TimeSpan.FromDays(7);
        var weekTokens = new TokenUsage();
        var byDay = new Dictionary<DateTimeOffset, (long Tokens, double Cost)>();
        var byHour = new Dictionary<DateTimeOffset, long>();
        var byModel = new Dictionary<string, TokenUsage>();
        foreach (var (info, start) in perFile)
        {
            if (start < weekCutoff) continue;
            weekTokens += info.Totals;
            var cost = PricingTable.CostUsd(DefaultModel, info.Totals);
            var day = new DateTimeOffset(start.UtcDateTime.Date, TimeSpan.Zero);
            var current = byDay.GetValueOrDefault(day, (0, 0));
            byDay[day] = (current.Tokens + info.Totals.Total, current.Cost + cost);
            var hour = FlooredToHour(start);
            byHour[hour] = byHour.GetValueOrDefault(hour) + info.Totals.Total;
            var model = info.Model ?? "unknown";
            byModel[model] = byModel.GetValueOrDefault(model) + info.Totals;
        }

        var breakdown = byModel
            .Select(kv => new ModelUsage { Model = kv.Key, Tokens = kv.Value.Total, CostUsd = PricingTable.CostUsd(kv.Key, kv.Value) })
            .OrderByDescending(m => m.Tokens)
            .ToList();

        var weekly = new WeeklyUsage
        {
            Tokens = weekTokens,
            Cost = new CostEstimate { AmountUsd = PricingTable.CostUsd(DefaultModel, weekTokens) },
            UsedPercent = weeklyWindow?.UsedPercent,
            ResetsAt = weeklyWindow?.ResetsAt,
            DailyTotals = byDay.Select(kv => new DailyTotal { Day = kv.Key, Tokens = kv.Value.Tokens, CostUsd = kv.Value.Cost })
                .OrderBy(d => d.Day).ToList(),
            HourlyTotals = byHour.Select(kv => new HourlyTotal { Hour = kv.Key, Tokens = kv.Value })
                .OrderBy(h => h.Hour).ToList(),
        };

        var noteParts = new[] { latest.LimitName, latest.PlanType is { } pt ? $"Plan: {pt}" : null }
            .Where(p => !string.IsNullOrEmpty(p));
        var note = string.Join(" · ", noteParts);

        return Task.FromResult(new UsageSnapshot
        {
            Provider = Id,
            CapturedAt = now,
            Health = failedFiles > 0 ? ProviderHealth.Degraded : ProviderHealth.Ok,
            Session = session,
            Weekly = weekly,
            ActiveModel = latest.Model ?? DefaultModel,
            LastActivityAt = latest.Timestamp,
            Note = string.IsNullOrEmpty(note) ? null : note,
            ModelBreakdown = breakdown.Count > 0 ? breakdown : null,
        });
    }

    private static DateTimeOffset FlooredToHour(DateTimeOffset date)
    {
        var epoch = date.ToUnixTimeSeconds();
        return DateTimeOffset.FromUnixTimeSeconds((epoch / 3600) * 3600);
    }
}
