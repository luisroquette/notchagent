using NotchAgent.Windows.Models;

namespace NotchAgent.Windows.Services;

/// Escalating "space left" alert logic — ported verbatim from the Mac app.
public static class ThresholdAlerts
{
    public static readonly int[] Levels = { 25, 15, 10, 5 };
    /// Re-arm only after the gauge climbs clearly above the top threshold,
    /// so jitter around a boundary can't re-fire the same alert.
    public const double ResetAbove = 27;

    /// The deepest threshold newly crossed, or null.
    public static int? NewCrossing(double remaining, HashSet<int> alreadyFired)
    {
        var candidates = Levels.Where(l => remaining <= l && !alreadyFired.Contains(l)).ToList();
        return candidates.Count > 0 ? candidates.Min() : null;
    }

    /// All thresholds the current value sits at or below.
    public static HashSet<int> Crossed(double remaining) => Levels.Where(l => remaining <= l).ToHashSet();

    public static bool ShouldReset(double remaining) => remaining > ResetAbove;

    public static Models.AttentionLevel AttentionLevel(int threshold) =>
        threshold <= 10 ? Models.AttentionLevel.Critical : Models.AttentionLevel.Warning;

    public static string Message(Models.ThresholdAlert alert)
    {
        var window = alert.IsWeekly ? "weekly limit" : "5h session";
        return $"{alert.Provider.DisplayName()}: {Math.Round(alert.Remaining)}% of the {window} left";
    }
}
