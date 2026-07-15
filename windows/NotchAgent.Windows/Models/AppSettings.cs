namespace NotchAgent.Windows.Models;

public enum ThemeMode
{
    Auto,
    Dark,
    Light,
}

public sealed class AppSettings
{
    public ThemeMode ThemeMode { get; set; } = ThemeMode.Auto;
    public double RefreshIntervalSeconds { get; set; } = 60;
    public double WarningThresholdPercent { get; set; } = 70;
    public double CriticalThresholdPercent { get; set; } = 90;
    public bool NotificationsEnabled { get; set; } = true;
    public bool RunnerEnabled { get; set; } = true;
    public bool ClaudeQuotaProbeEnabled { get; set; } = true;
    public int? ClaudeSessionTokenBudget { get; set; }
    public int? ClaudeWeeklyTokenBudget { get; set; }
    public bool LaunchAtLogin { get; set; }
}
