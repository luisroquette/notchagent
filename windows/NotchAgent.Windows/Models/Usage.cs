namespace NotchAgent.Windows.Models;

public struct TokenUsage
{
    public long Input;
    public long Output;
    public long CacheWrite;
    public long CacheRead;

    public readonly long Total => Input + Output + CacheWrite + CacheRead;

    public static TokenUsage operator +(TokenUsage a, TokenUsage b) => new()
    {
        Input = a.Input + b.Input,
        Output = a.Output + b.Output,
        CacheWrite = a.CacheWrite + b.CacheWrite,
        CacheRead = a.CacheRead + b.CacheRead,
    };
}

/// Always local math over public pricing tables — never presented as billing truth.
public sealed class CostEstimate
{
    public double AmountUsd { get; set; }
}

/// Usage inside the provider's current rate-limit session window (e.g. 5h block).
public sealed class SessionUsage
{
    public TokenUsage Tokens { get; set; }
    public CostEstimate? Cost { get; set; }
    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? ResetsAt { get; set; }
    /// 0–100. Null when the provider exposes no session limit locally.
    public double? UsedPercent { get; set; }
}

public sealed class DailyTotal
{
    public DateTimeOffset Day { get; set; }
    public long Tokens { get; set; }
    public double CostUsd { get; set; }
}

public sealed class HourlyTotal
{
    public DateTimeOffset Hour { get; set; }
    public long Tokens { get; set; }
}

/// Trailing 7-day usage (or the provider's own weekly window when it exposes one).
public sealed class WeeklyUsage
{
    public TokenUsage Tokens { get; set; }
    public CostEstimate? Cost { get; set; }
    public double? UsedPercent { get; set; }
    public DateTimeOffset? ResetsAt { get; set; }
    public List<DailyTotal> DailyTotals { get; set; } = new();
    public List<HourlyTotal>? HourlyTotals { get; set; }
}

public sealed class ModelUsage
{
    public string Model { get; set; } = "";
    public long Tokens { get; set; }
    public double CostUsd { get; set; }
}

/// Normalized output of every provider — the only shape the UI ever consumes.
public sealed class UsageSnapshot
{
    public required ProviderId Provider { get; init; }
    public DateTimeOffset CapturedAt { get; init; } = DateTimeOffset.UtcNow;
    public required ProviderHealth Health { get; init; }
    public SessionUsage? Session { get; init; }
    public WeeklyUsage? Weekly { get; init; }
    public string? ActiveModel { get; init; }
    public DateTimeOffset? LastActivityAt { get; init; }
    /// Human-readable caveat (e.g. "token data unavailable for this CLI").
    public string? Note { get; init; }
    public QuotaStatus? QuotaStatus { get; init; }
    public List<ModelUsage>? ModelBreakdown { get; init; }
}

/// The one gauge that matters everywhere: how much of the limit is LEFT.
/// Session window takes precedence; weekly is the fallback.
public readonly struct GaugeMetric
{
    public double Used { get; }
    public bool IsWeekly { get; }

    public GaugeMetric(double used, bool isWeekly)
    {
        Used = used;
        IsWeekly = isWeekly;
    }

    public double Remaining => Math.Max(0, 100 - Used);

    /// The API's "rejected" status is more authoritative than any percent
    /// math: if the account is blocked, the gauge must show empty — never a
    /// calm green number that contradicts a BLOCKED badge on the same card.
    public static GaugeMetric? From(UsageSnapshot? snapshot)
    {
        if (snapshot?.QuotaStatus == Models.QuotaStatus.Blocked)
        {
            var isWeekly = snapshot.Session?.UsedPercent is null && snapshot.Weekly?.UsedPercent is not null;
            return new GaugeMetric(100, isWeekly);
        }
        if (snapshot?.Session?.UsedPercent is { } sessionPercent)
        {
            return new GaugeMetric(sessionPercent, false);
        }
        if (snapshot?.Weekly?.UsedPercent is { } weeklyPercent)
        {
            return new GaugeMetric(weeklyPercent, true);
        }
        return null;
    }
}
