using Avalonia.Media;
using NotchAgent.Windows.Models;

namespace NotchAgent.Windows.UI;

/// Design tokens mirroring the Mac app's "retro hardware gauge" language —
/// coral accent, state-colored numerals, chunky segmented meters.
public static class AppTheme
{
    public static readonly Color Coral = Color.FromRgb(218, 119, 87);
    public static readonly Color CoralDim = Color.FromArgb(140, 218, 119, 87);
    public static readonly Color Ok = Color.FromRgb(122, 197, 127);
    public static readonly Color Caution = Color.FromRgb(232, 195, 90);
    public static readonly Color Warning = Color.FromRgb(239, 169, 78);
    public static readonly Color Danger = Color.FromRgb(229, 72, 77);

    public static readonly Color Surface = Color.FromRgb(22, 22, 27);
    public static readonly Color SurfaceRaised = Color.FromRgb(32, 32, 38);
    public static readonly Color Hairline = Color.FromArgb(20, 255, 255, 255);
    public static readonly Color TextPrimary = Color.FromArgb(237, 255, 255, 255);
    public static readonly Color TextSecondary = Color.FromArgb(158, 255, 255, 255);
    public static readonly Color TextDim = Color.FromArgb(107, 255, 255, 255);
    public static readonly Color TextFaint = Color.FromArgb(66, 255, 255, 255);
    public static readonly Color Socket = Color.FromArgb(26, 255, 255, 255);

    public static IBrush Brush(Color c) => new SolidColorBrush(c);

    /// Stick-style color ramp for utilization percentages.
    public static Color Ramp(double percent, double warningAt = 70, double criticalAt = 90) => percent switch
    {
        var p when p >= criticalAt => Danger,
        var p when p >= warningAt => Warning,
        var p when p >= 50 => Caution,
        _ => Ok,
    };

    /// State coherence rule: when the burn projection or blocked status says
    /// the window is effectively empty, no gauge may look calmer than warning.
    public static Color RiskTint(double used, bool projectedToRunOut, double warningAt = 70, double criticalAt = 90)
    {
        var baseColor = Ramp(used, warningAt, criticalAt);
        if (!projectedToRunOut || baseColor == Danger) return baseColor;
        return Warning;
    }

    public static Color AttentionColor(AttentionLevel level) => level switch
    {
        AttentionLevel.Critical => Danger,
        AttentionLevel.Warning => Warning,
        _ => Ok,
    };
}
