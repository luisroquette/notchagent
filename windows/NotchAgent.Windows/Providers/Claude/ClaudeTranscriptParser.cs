using System.Text;
using System.Text.Json;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Providers.Shared;

namespace NotchAgent.Windows.Providers.Claude;

public sealed class ClaudeFileStat
{
    public sealed class HourStat
    {
        public TokenUsage Tokens;
        public double CostUsd;
        public int Messages;
    }

    public sealed class ModelStat
    {
        public TokenUsage Tokens;
        public double CostUsd;
    }

    public Dictionary<DateTimeOffset, HourStat> Hours { get; } = new();
    public Dictionary<string, ModelStat> ByModel { get; } = new();
    public DateTimeOffset? LastActivity { get; set; }
    public string? LastModel { get; set; }
    public int UsageLineCount { get; set; }
    /// Dedup keys survive incremental re-parses of the same file.
    public HashSet<string> SeenKeys { get; } = new();
}

public static class ClaudeTranscriptParser
{
    private static readonly byte[] UsageMarker = Encoding.UTF8.GetBytes("\"usage\"");
    private static readonly byte[] AssistantMarker = Encoding.UTF8.GetBytes("\"assistant\"");

    /// Byte-level pre-filter: transcripts carry multi-megabyte lines (base64
    /// images, tool dumps) that can never be usage records. This skips them
    /// before the expensive JSON parse ever runs.
    public static bool QuickMatch(ReadOnlySpan<byte> line) =>
        line.IndexOf(UsageMarker) >= 0 && line.IndexOf(AssistantMarker) >= 0;

    public static DateTimeOffset FlooredToHour(DateTimeOffset date)
    {
        var epoch = date.ToUnixTimeSeconds();
        var flooredHours = (epoch / 3600) * 3600;
        return DateTimeOffset.FromUnixTimeSeconds(flooredHours);
    }

    /// Tolerant: malformed lines are skipped, only assistant lines with usage count.
    /// Deduplicates by requestId/message.id. Incremental: pass `from`/`into` to
    /// parse only bytes appended since the last scan.
    public static (ClaudeFileStat Stat, long Consumed) ParseFile(string path, long offset = 0, ClaudeFileStat? baseStat = null)
    {
        var stat = baseStat ?? new ClaudeFileStat();

        long consumed = JsonlReader.ForEachLine(path, offset, lineBytes =>
        {
            if (!QuickMatch(lineBytes.Span)) return;

            JsonDocument doc;
            try { doc = JsonDocument.Parse(lineBytes); }
            catch (JsonException) { return; }
            using (doc)
            {
                var root = doc.RootElement;
                if (!root.TryGetProperty("type", out var typeProp) || typeProp.GetString() != "assistant") return;
                if (!root.TryGetProperty("message", out var message)) return;
                if (!message.TryGetProperty("usage", out var usage)) return;
                if (!root.TryGetProperty("timestamp", out var tsProp)) return;
                if (!DateTimeOffset.TryParse(tsProp.GetString(), out var timestamp)) return;

                string? key = root.TryGetProperty("requestId", out var rid) ? rid.GetString()
                    : message.TryGetProperty("id", out var mid) ? mid.GetString() : null;
                if (key is not null && !stat.SeenKeys.Add(key)) return;

                string model = message.TryGetProperty("model", out var m) ? (m.GetString() ?? "claude") : "claude";
                var tokens = new TokenUsage
                {
                    Input = GetLong(usage, "input_tokens"),
                    Output = GetLong(usage, "output_tokens"),
                    CacheWrite = GetLong(usage, "cache_creation_input_tokens"),
                    CacheRead = GetLong(usage, "cache_read_input_tokens"),
                };
                var cost = PricingTable.CostUsd(model, tokens);

                var hour = FlooredToHour(timestamp);
                if (!stat.Hours.TryGetValue(hour, out var bucket))
                {
                    bucket = new ClaudeFileStat.HourStat();
                    stat.Hours[hour] = bucket;
                }
                bucket.Tokens += tokens;
                bucket.CostUsd += cost;
                bucket.Messages += 1;

                if (!stat.ByModel.TryGetValue(model, out var modelStat))
                {
                    modelStat = new ClaudeFileStat.ModelStat();
                    stat.ByModel[model] = modelStat;
                }
                modelStat.Tokens += tokens;
                modelStat.CostUsd += cost;

                if (stat.LastActivity is null || timestamp > stat.LastActivity)
                {
                    stat.LastActivity = timestamp;
                    stat.LastModel = model;
                }
                stat.UsageLineCount += 1;
            }
        });

        return (stat, consumed);
    }

    private static long GetLong(JsonElement obj, string prop) =>
        obj.TryGetProperty(prop, out var v) && v.TryGetInt64(out var n) ? n : 0;
}

/// Incremental per-file cache: unchanged files hit the cache, grown files
/// parse only the appended bytes, truncated/rotated files re-parse fully.
public sealed class ClaudeScanCache
{
    private sealed record Entry(FileStamp Stamp, long Offset, ClaudeFileStat Stat);

    private readonly Dictionary<string, Entry> _entries = new();
    private readonly object _lock = new();

    public ClaudeFileStat? Stat(string path)
    {
        var stamp = FileStamp.Of(path);
        if (stamp is not { } s) return null;

        lock (_lock)
        {
            if (_entries.TryGetValue(path, out var entry))
            {
                if (entry.Stamp.Equals(s)) return entry.Stat;
                if (s.Size >= entry.Offset)
                {
                    var (stat, consumed) = ClaudeTranscriptParser.ParseFile(path, entry.Offset, entry.Stat);
                    _entries[path] = new Entry(s, consumed, stat);
                    return stat;
                }
                // File shrank — rotated or rewritten. Fall through to a full parse.
            }
            var (fullStat, fullConsumed) = ClaudeTranscriptParser.ParseFile(path);
            _entries[path] = new Entry(s, fullConsumed, fullStat);
            return fullStat;
        }
    }

    /// Drops entries for files no longer in the scan set.
    public void Prune(HashSet<string> keep)
    {
        lock (_lock)
        {
            foreach (var key in _entries.Keys.Where(k => !keep.Contains(k)).ToList())
            {
                _entries.Remove(key);
            }
        }
    }
}
