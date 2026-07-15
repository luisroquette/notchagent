namespace NotchAgent.Windows.Models;

/// Stable identifier for each monitored AI provider. Mirrors the Mac app's
/// ProviderID exactly so the two products stay conceptually identical.
public enum ProviderId
{
    ClaudeCode,
    Codex,
}

public static class ProviderIdExtensions
{
    public static string DisplayName(this ProviderId id) => id switch
    {
        ProviderId.ClaudeCode => "Claude Code",
        ProviderId.Codex => "Codex",
        _ => id.ToString(),
    };

    public static string ShortName(this ProviderId id) => id switch
    {
        ProviderId.ClaudeCode => "Claude",
        ProviderId.Codex => "Codex",
        _ => id.ToString(),
    };
}

public enum ProviderHealth
{
    Ok,
    Degraded,
    ParseError,
    NotInstalled,
    NoData,
}

public static class ProviderHealthExtensions
{
    public static bool IsUsable(this ProviderHealth health) =>
        health is ProviderHealth.Ok or ProviderHealth.Degraded or ProviderHealth.NoData;

    public static string BadgeText(this ProviderHealth health) => health switch
    {
        ProviderHealth.Ok => "OK",
        ProviderHealth.Degraded => "Degraded",
        ProviderHealth.ParseError => "Parse error",
        ProviderHealth.NotInstalled => "Not installed",
        ProviderHealth.NoData => "No data",
        _ => health.ToString(),
    };
}

/// Authoritative rate-limit state reported by the provider's API
/// (`anthropic-ratelimit-unified-status` for Claude).
public enum QuotaStatus
{
    Ok,
    Warning,
    Blocked,
}

public enum AttentionLevel
{
    Normal = 0,
    Warning = 1,
    Critical = 2,
}
