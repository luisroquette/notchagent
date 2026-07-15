using System.Globalization;

namespace NotchAgent.Windows.Services;

public static class Format
{
    /// 950 → "950", 12_400 → "12.4k", 3_400_000 → "3.4M"
    public static string Tokens(long n)
    {
        double value = n;
        return value switch
        {
            < 1_000 => n.ToString(CultureInfo.InvariantCulture),
            < 1_000_000 => Trimmed(value / 1_000) + "k",
            < 1_000_000_000 => Trimmed(value / 1_000_000) + "M",
            _ => Trimmed(value / 1_000_000_000) + "B",
        };
    }

    public static string Percent(double v) => $"{Math.Round(v)}%";

    public static string Usd(double v) => $"${v:0.00}";

    public static string Time(DateTimeOffset date) => date.ToLocalTime().ToString("HH:mm", CultureInfo.InvariantCulture);

    public static string Relative(DateTimeOffset date, DateTimeOffset? reference = null)
    {
        var now = reference ?? DateTimeOffset.UtcNow;
        var seconds = (now - date).TotalSeconds;
        if (seconds < 60) return "now";
        var minutes = seconds / 60;
        if (minutes < 60) return $"{(int)minutes}m ago";
        var hours = minutes / 60;
        if (hours < 24) return $"{(int)hours}h ago";
        return $"{(int)(hours / 24)}d ago";
    }

    /// "2h 14m" until `date`; "now" when past.
    public static string Countdown(DateTimeOffset date, DateTimeOffset? reference = null)
    {
        var now = reference ?? DateTimeOffset.UtcNow;
        var seconds = (date - now).TotalSeconds;
        if (seconds <= 0) return "now";
        var hours = (int)(seconds / 3600);
        var minutes = (int)(seconds % 3600 / 60);
        if (hours > 48) return $"{hours / 24}d {hours % 24}h";
        if (hours > 0) return $"{hours}h {minutes}m";
        return $"{minutes}m";
    }

    private static string Trimmed(double value)
    {
        var s = value.ToString("0.0", CultureInfo.InvariantCulture);
        return s.EndsWith(".0") ? s[..^2] : s;
    }
}
