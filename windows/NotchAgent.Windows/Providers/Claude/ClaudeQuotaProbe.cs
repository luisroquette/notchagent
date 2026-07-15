using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using NotchAgent.Windows.Providers.Shared;
using NotchAgent.Windows.Services;

namespace NotchAgent.Windows.Providers.Claude;

public enum ClaudeQuotaStatus { Ok, Warning, Blocked }

public sealed record ClaudeQuota(
    double? SessionPercent,
    double? WeeklyPercent,
    DateTimeOffset? SessionResetsAt,
    DateTimeOffset? WeeklyResetsAt,
    ClaudeQuotaStatus? Status,
    string? LimitingWindow,
    DateTimeOffset FetchedAt);

/// Locates the Claude Code OAuth token without ever logging or persisting it.
/// Order: env var → %USERPROFILE%\.claude\.credentials.json (same JSON format
/// Claude Code writes on macOS, just a Windows path).
public static class ClaudeTokenLocator
{
    public static string? OauthToken()
    {
        var env = Environment.GetEnvironmentVariable("CLAUDE_CODE_OAUTH_TOKEN");
        if (!string.IsNullOrEmpty(env)) return env;

        var file = Path.Combine(AppPaths.Home, ".claude", ".credentials.json");
        if (!File.Exists(file)) return null;
        try
        {
            return ParseCredentials(File.ReadAllBytes(file));
        }
        catch (IOException)
        {
            return null;
        }
    }

    public static string? ParseCredentials(byte[] data, DateTimeOffset? now = null)
    {
        var reference = now ?? DateTimeOffset.UtcNow;
        try
        {
            using var doc = JsonDocument.Parse(data);
            if (!doc.RootElement.TryGetProperty("claudeAiOauth", out var oauth)) return null;
            if (!oauth.TryGetProperty("accessToken", out var tokenProp)) return null;
            var token = tokenProp.GetString();
            if (string.IsNullOrEmpty(token)) return null;

            if (oauth.TryGetProperty("expiresAt", out var expiresProp) && expiresProp.TryGetDouble(out var expiresMs))
            {
                var expiresAt = DateTimeOffset.FromUnixTimeMilliseconds((long)expiresMs);
                if (expiresAt < reference) return null;
            }
            return token;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// Authoritative Claude quota read from Anthropic API response headers
/// (`anthropic-ratelimit-unified-*`), the same technique used by
/// claude-usage-stick: a `max_tokens: 1` request whose body is discarded —
/// only the rate-limit headers matter. Quota impact is negligible (1 token).
public sealed class ClaudeQuotaProbe
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };
    private readonly TimeSpan _minInterval;
    private ClaudeQuota? _cache;
    private DateTimeOffset _lastAttempt = DateTimeOffset.MinValue;
    private bool _missingTokenLogged;

    public ClaudeQuotaProbe(TimeSpan? minInterval = null)
    {
        _minInterval = minInterval ?? TimeSpan.FromSeconds(60);
    }

    public async Task<ClaudeQuota?> CurrentQuotaAsync(CancellationToken ct)
    {
        if (DateTimeOffset.UtcNow - _lastAttempt < _minInterval)
        {
            return _cache;
        }
        var token = ClaudeTokenLocator.OauthToken();
        if (token is null)
        {
            if (!_missingTokenLogged)
            {
                _missingTokenLogged = true;
                Log.Providers.LogInformation("claude probe: no OAuth token found — falling back to local budgets");
            }
            _lastAttempt = DateTimeOffset.UtcNow;
            return _cache;
        }
        _missingTokenLogged = false;
        _lastAttempt = DateTimeOffset.UtcNow;

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages");
            request.Headers.Add("Authorization", $"Bearer {token}");
            request.Headers.Add("anthropic-beta", "oauth-2025-04-20");
            request.Headers.Add("anthropic-version", "2023-06-01");
            request.Headers.UserAgent.ParseAdd("claude-cli/2.1.207 (external, cli)");
            request.Content = new StringContent(
                """{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}""",
                new MediaTypeHeaderValue("application/json"));

            using var response = await Http.SendAsync(request, ct);
            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var h in response.Headers) headers[h.Key] = string.Join(",", h.Value);
            if (response.Content.Headers is not null)
            {
                foreach (var h in response.Content.Headers) headers[h.Key] = string.Join(",", h.Value);
            }

            var quota = Parse(headers);
            if (quota.SessionPercent is not null || quota.WeeklyPercent is not null)
            {
                _cache = quota;
                Log.Providers.LogDebug("claude probe ok (http {0})", (int)response.StatusCode);
            }
            else
            {
                Log.Providers.LogError("claude probe: no rate-limit headers (http {0})", (int)response.StatusCode);
            }
            return _cache;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            Log.Providers.LogError("claude probe failed: {0}", ex.Message);
            return _cache;
        }
    }

    /// Pure and testable. Keys must be lowercase-insensitive (dictionary is
    /// case-insensitive already).
    public static ClaudeQuota Parse(IReadOnlyDictionary<string, string> headers, DateTimeOffset? now = null)
    {
        return new ClaudeQuota(
            SessionPercent: Percent(Get(headers, "anthropic-ratelimit-unified-5h-utilization")),
            WeeklyPercent: Percent(Get(headers, "anthropic-ratelimit-unified-7d-utilization")),
            SessionResetsAt: ResetDate(Get(headers, "anthropic-ratelimit-unified-5h-reset")),
            WeeklyResetsAt: ResetDate(Get(headers, "anthropic-ratelimit-unified-7d-reset")),
            Status: Status(Get(headers, "anthropic-ratelimit-unified-status")),
            LimitingWindow: Get(headers, "anthropic-ratelimit-unified-representative-claim"),
            FetchedAt: now ?? DateTimeOffset.UtcNow);
    }

    private static string? Get(IReadOnlyDictionary<string, string> headers, string key) =>
        headers.TryGetValue(key, out var v) ? v : null;

    /// Utilization arrives on a 0–1 scale; tolerate a switch to 0–100. Only
    /// values ≤ 1.0 (mathematically valid utilizations) are treated as the
    /// 0–1 scale — anything above passes through as a percentage. If the
    /// scale is ambiguous we err toward UNDERSTATING (a quiet gauge) rather
    /// than a false 100% that would fire the whole alert cascade.
    private static double? Percent(string? raw)
    {
        if (raw is null || !double.TryParse(raw, out var value)) return null;
        var scaled = value <= 1.0 ? value * 100 : value;
        return Math.Min(Math.Max(scaled, 0), 100);
    }

    private static DateTimeOffset? ResetDate(string? raw)
    {
        if (raw is null) return null;
        if (double.TryParse(raw, out var epoch) && epoch > 1_000_000_000)
        {
            return DateTimeOffset.FromUnixTimeSeconds((long)epoch);
        }
        return DateTimeOffset.TryParse(raw, out var date) ? date : null;
    }

    private static ClaudeQuotaStatus? Status(string? raw) => raw switch
    {
        "allowed" => ClaudeQuotaStatus.Ok,
        "allowed_warning" => ClaudeQuotaStatus.Warning,
        "rejected" => ClaudeQuotaStatus.Blocked,
        _ => null,
    };
}
