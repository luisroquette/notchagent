using System.ComponentModel;
using System.Runtime.CompilerServices;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Services;

namespace NotchAgent.Windows.UI;

public sealed class BarViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? n = null) => PropertyChanged?.Invoke(this, new(n));

    private readonly UsageStore _store;
    public ProviderCardViewModel Claude { get; } = new(ProviderId.ClaudeCode);
    public ProviderCardViewModel Codex { get; } = new(ProviderId.Codex);

    public bool IsPaused => _store.IsPaused;
    public string PauseLabel => _store.IsPaused ? "Resume" : "Pause";

    public bool HasBanner { get; private set; }
    public string BannerText { get; private set; } = "";
    public Avalonia.Media.IBrush BannerColor { get; private set; } = AppTheme.Brush(AppTheme.Warning);

    public double RunnerUsedPercent { get; private set; }
    public bool RunnerGameOver { get; private set; }
    public DateTimeOffset? RunnerResetsAt { get; private set; }
    public Avalonia.Media.Color RunnerObstacleTint { get; private set; } = AppTheme.Coral;

    public string UpdatedText { get; private set; } = "waiting…";
    public Avalonia.Media.IBrush OverallAttentionColor { get; private set; } = AppTheme.Brush(AppTheme.Ok);

    public BarViewModel(UsageStore store)
    {
        _store = store;
        _store.PropertyChanged += (_, _) => Refresh();
        Refresh();
    }

    public void Refresh()
    {
        var settings = _store.Settings;
        _store.Snapshots.TryGetValue(ProviderId.ClaudeCode, out var claudeSnap);
        _store.Snapshots.TryGetValue(ProviderId.Codex, out var codexSnap);

        Claude.Update(claudeSnap, _store.Attention(ProviderId.ClaudeCode),
            _store.RefreshStates.GetValueOrDefault(ProviderId.ClaudeCode, RefreshState.IdleValue), settings);
        Codex.Update(codexSnap, _store.Attention(ProviderId.Codex),
            _store.RefreshStates.GetValueOrDefault(ProviderId.Codex, RefreshState.IdleValue), settings);

        if (_store.ActiveThresholdAlert is { } alert)
        {
            HasBanner = true;
            BannerText = ThresholdAlerts.Message(alert);
            BannerColor = AppTheme.Brush(AppTheme.AttentionColor(ThresholdAlerts.AttentionLevel(alert.Threshold)));
        }
        else if (_store.ActiveRestoreMoment is { } restore)
        {
            HasBanner = true;
            BannerText = restore.Message;
            BannerColor = AppTheme.Brush(AppTheme.Ok);
        }
        else
        {
            HasBanner = false;
        }

        var claudeMetric = GaugeMetric.From(claudeSnap);
        RunnerUsedPercent = claudeMetric?.Used ?? 0;
        RunnerGameOver = RunnerUsedPercent >= 99.5 || claudeSnap?.QuotaStatus == Models.QuotaStatus.Blocked;
        RunnerResetsAt = claudeMetric?.IsWeekly == true ? claudeSnap?.Weekly?.ResetsAt : claudeSnap?.Session?.ResetsAt;
        RunnerObstacleTint = AppTheme.Ramp(RunnerUsedPercent, settings.WarningThresholdPercent, settings.CriticalThresholdPercent);

        var lastSuccess = _store.RefreshStates.Values
            .OfType<RefreshState.Success>()
            .Select(s => (DateTimeOffset?)s.Date)
            .DefaultIfEmpty(null)
            .Max();
        UpdatedText = lastSuccess is { } date ? $"updated {Format.Relative(date)}" : "waiting…";
        OverallAttentionColor = AppTheme.Brush(AppTheme.AttentionColor(_store.OverallAttention));

        RaiseAll();
    }

    private void RaiseAll()
    {
        foreach (var prop in typeof(BarViewModel).GetProperties()) Raise(prop.Name);
    }
}
