namespace NotchAgent.Windows.Models;

public sealed class UsageEvent
{
    public enum EventKind { Alert, Error, Info }

    public Guid Id { get; } = Guid.NewGuid();
    public DateTimeOffset Date { get; init; } = DateTimeOffset.UtcNow;
    public ProviderId? Provider { get; init; }
    public required EventKind Kind { get; init; }
    public AttentionLevel Level { get; init; } = AttentionLevel.Normal;
    public required string Message { get; init; }
}

public sealed record ProviderAlert(ProviderId Provider, AttentionLevel Level, string Message)
{
    public DateTimeOffset Date { get; } = DateTimeOffset.UtcNow;
}

/// Escalating "space left" alert fired when a provider's gauge crosses below
/// 25 / 15 / 10 / 5 percent remaining. Each threshold fires once per window;
/// everything re-arms when the window resets (remaining climbs back up).
public sealed record ThresholdAlert(ProviderId Provider, int Threshold, double Remaining, bool IsWeekly)
{
    public DateTimeOffset FiredAt { get; } = DateTimeOffset.UtcNow;
}

/// The positive counterpart to a low-fuel alert: fired once when a provider
/// transitions from blocked back to usable while the user was recently active.
public sealed record RestoreMoment(ProviderId Provider, double Remaining, bool IsWeekly)
{
    public DateTimeOffset FiredAt { get; } = DateTimeOffset.UtcNow;

    public string Message =>
        $"{Provider.DisplayName()} is back — {Math.Round(Remaining)}% of the {(IsWeekly ? "weekly limit" : "5h session")} left";
}
