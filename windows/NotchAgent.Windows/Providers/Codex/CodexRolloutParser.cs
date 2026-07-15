using System.Text.Json;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Providers.Shared;

namespace NotchAgent.Windows.Providers.Codex;

/// Codex CLI rollouts emit `token_count` events carrying cumulative totals AND
/// authoritative rate-limit percentages for the 5h (primary) and weekly
/// (secondary) windows.
public sealed record CodexRateWindow(double UsedPercent, int? WindowMinutes, DateTimeOffset? ResetsAt);

public sealed class CodexTokenInfo
{
    public DateTimeOffset? Timestamp { get; init; }
    /// Normalized: Input excludes cached tokens, cached input goes to CacheRead.
    public TokenUsage Totals { get; init; }
    public CodexRateWindow? Primary { get; init; }
    public CodexRateWindow? Secondary { get; init; }
    public string? PlanType { get; init; }
    public string? LimitName { get; init; }
    public string? Model { get; init; }

    /// Codex changes window semantics per plan (some plans report a single
    /// weekly window as `primary`, `secondary: null`). Classify by duration
    /// instead of position.
    public CodexRateWindow? SessionWindow =>
        new[] { Primary, Secondary }.FirstOrDefault(w => w is not null && (w.WindowMinutes ?? 0) <= 24 * 60);

    public CodexRateWindow? WeeklyWindow =>
        new[] { Primary, Secondary }.FirstOrDefault(w => w is not null && (w.WindowMinutes ?? 0) > 24 * 60);
}

public static class CodexRolloutParser
{
    /// Scans the file tail backwards for the newest `token_count` event and
    /// the newest `turn_context` (which names the model). Tail-only keeps
    /// refreshes cheap even on very long rollouts.
    public static CodexTokenInfo? LatestTokenInfo(string path, int tailBytes = 2 * 1024 * 1024)
    {
        var lines = JsonlReader.TailLines(path, tailBytes);
        DateTimeOffset? timestamp = null;
        TokenUsage totals = default;
        CodexRateWindow? primary = null;
        CodexRateWindow? secondary = null;
        string? planType = null;
        string? limitName = null;
        string? model = null;
        bool haveInfo = false;

        for (int i = lines.Count - 1; i >= 0; i--)
        {
            var data = lines[i];
            if (!haveInfo && TryParseTokenCount(data, out var info))
            {
                timestamp = info.Timestamp;
                totals = info.Totals;
                primary = info.Primary;
                secondary = info.Secondary;
                planType = info.PlanType;
                limitName = info.LimitName;
                haveInfo = true;
            }
            if (model is null && TryParseTurnContext(data, out var contextModel))
            {
                model = contextModel;
            }
            if (haveInfo && model is not null) break;
        }

        if (!haveInfo) return null;
        return new CodexTokenInfo
        {
            Timestamp = timestamp,
            Totals = totals,
            Primary = primary,
            Secondary = secondary,
            PlanType = planType,
            LimitName = limitName,
            Model = model,
        };
    }

    private static bool TryParseTokenCount(byte[] data, out CodexTokenInfo info)
    {
        info = new CodexTokenInfo();
        try
        {
            using var doc = JsonDocument.Parse(data);
            var root = doc.RootElement;
            if (!root.TryGetProperty("payload", out var payload)) return false;
            if (!payload.TryGetProperty("type", out var typeProp) || typeProp.GetString() != "token_count") return false;

            DateTimeOffset? timestamp = root.TryGetProperty("timestamp", out var tsProp)
                && DateTimeOffset.TryParse(tsProp.GetString(), out var ts) ? ts : null;

            long input = 0, cached = 0, output = 0;
            if (payload.TryGetProperty("info", out var infoObj) &&
                infoObj.TryGetProperty("total_token_usage", out var totalUsage))
            {
                input = GetLong(totalUsage, "input_tokens");
                cached = GetLong(totalUsage, "cached_input_tokens");
                output = GetLong(totalUsage, "output_tokens");
            }
            var totals = new TokenUsage
            {
                Input = Math.Max(0, input - cached),
                Output = output,
                CacheWrite = 0,
                CacheRead = cached,
            };

            CodexRateWindow? primary = null, secondary = null;
            string? planType = null, limitName = null;
            if (payload.TryGetProperty("rate_limits", out var rateLimits) && rateLimits.ValueKind == JsonValueKind.Object)
            {
                primary = ParseWindow(rateLimits, "primary");
                secondary = ParseWindow(rateLimits, "secondary");
                planType = rateLimits.TryGetProperty("plan_type", out var pt) ? pt.GetString() : null;
                limitName = rateLimits.TryGetProperty("limit_name", out var ln) ? ln.GetString() : null;
            }

            info = new CodexTokenInfo
            {
                Timestamp = timestamp,
                Totals = totals,
                Primary = primary,
                Secondary = secondary,
                PlanType = planType,
                LimitName = limitName,
            };
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool TryParseTurnContext(byte[] data, out string? model)
    {
        model = null;
        try
        {
            using var doc = JsonDocument.Parse(data);
            var root = doc.RootElement;
            if (!root.TryGetProperty("type", out var typeProp) || typeProp.GetString() != "turn_context") return false;
            if (!root.TryGetProperty("payload", out var payload)) return false;
            if (payload.TryGetProperty("model", out var modelProp))
            {
                model = modelProp.GetString();
                return model is not null;
            }
            return false;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static CodexRateWindow? ParseWindow(JsonElement rateLimits, string key)
    {
        if (!rateLimits.TryGetProperty(key, out var window) || window.ValueKind != JsonValueKind.Object) return null;
        if (!window.TryGetProperty("used_percent", out var usedProp) || !usedProp.TryGetDouble(out var used)) return null;
        int? minutes = window.TryGetProperty("window_minutes", out var m) && m.TryGetInt32(out var mi) ? mi : null;
        DateTimeOffset? resetsAt = window.TryGetProperty("resets_at", out var r) && r.TryGetDouble(out var epoch)
            ? DateTimeOffset.FromUnixTimeSeconds((long)epoch) : null;
        return new CodexRateWindow(used, minutes, resetsAt);
    }

    private static long GetLong(JsonElement obj, string prop) =>
        obj.TryGetProperty(prop, out var v) && v.TryGetInt64(out var n) ? n : 0;
}
