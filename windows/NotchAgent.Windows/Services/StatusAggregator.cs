using NotchAgent.Windows.Models;

namespace NotchAgent.Windows.Services;

/// Pure functions that consolidate raw snapshots into UI-facing status.
public static class StatusAggregator
{
    public static AttentionLevel Attention(UsageSnapshot snapshot, AppSettings settings)
    {
        var worst = AttentionLevel.Normal;
        if (snapshot.Health is ProviderHealth.ParseError or ProviderHealth.Degraded)
        {
            worst = AttentionLevel.Warning;
        }
        // API-reported limit state is authoritative and overrides percent math.
        switch (snapshot.QuotaStatus)
        {
            case Models.QuotaStatus.Blocked:
                worst = AttentionLevel.Critical;
                break;
            case Models.QuotaStatus.Warning:
                worst = Max(worst, AttentionLevel.Warning);
                break;
        }

        var percents = new[] { snapshot.Session?.UsedPercent, snapshot.Weekly?.UsedPercent }
            .Where(p => p is not null).Select(p => p!.Value);
        foreach (var percent in percents)
        {
            if (percent >= settings.CriticalThresholdPercent) worst = Max(worst, AttentionLevel.Critical);
            else if (percent >= settings.WarningThresholdPercent) worst = Max(worst, AttentionLevel.Warning);
        }
        return worst;
    }

    public static AttentionLevel OverallAttention(IEnumerable<UsageSnapshot> snapshots, AppSettings settings)
    {
        var levels = snapshots.Select(s => Attention(s, settings)).ToList();
        return levels.Count > 0 ? levels.Max() : AttentionLevel.Normal;
    }

    public static List<ProviderAlert> TransitionAlerts(
        Dictionary<ProviderId, UsageSnapshot> old, UsageSnapshot snapshot, AppSettings settings)
    {
        // Placeholder for future health-transition alerts (mirrors Mac's hook
        // point); threshold-based alerts are handled separately in UsageStore.
        return new List<ProviderAlert>();
    }

    private static AttentionLevel Max(AttentionLevel a, AttentionLevel b) => (AttentionLevel)Math.Max((int)a, (int)b);
}
