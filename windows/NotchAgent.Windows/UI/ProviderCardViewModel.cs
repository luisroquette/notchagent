using System.ComponentModel;
using System.Runtime.CompilerServices;
using Avalonia.Media;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Services;

namespace NotchAgent.Windows.UI;

/// Precomputed, bindable strings/colors for one provider card — mirrors
/// ProviderCardView.swift's computed properties so the XAML stays simple.
public sealed class ProviderCardViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? n = null) => PropertyChanged?.Invoke(this, new(n));

    public ProviderId Provider { get; }
    public string ProviderName => Provider.ShortName();
    public string SymbolText => Provider == ProviderId.ClaudeCode ? "✳" : "</>";

    public bool HasGauge { get; private set; }
    public string HeroText { get; private set; } = "—";
    public IBrush HeroColor { get; private set; } = AppTheme.Brush(AppTheme.TextPrimary);
    public string WindowLabel { get; private set; } = "";
    public double MeterPercent { get; private set; }
    public IBrush MeterColor { get; private set; } = AppTheme.Brush(AppTheme.Coral);
    public string ResetLine { get; private set; } = "";
    public string CountdownText { get; private set; } = "";
    public bool HasReset { get; private set; }
    public string UsageLine { get; private set; } = "";
    public bool HasUsageLine { get; private set; }
    public string NoteText { get; private set; } = "";
    public bool HasNote { get; private set; }
    public string QuotaChipText { get; private set; } = "";
    public bool HasQuotaChip { get; private set; }
    public IBrush QuotaChipColor { get; private set; } = AppTheme.Brush(AppTheme.Warning);
    public string HealthBadgeText { get; private set; } = "";
    public IBrush HealthBadgeColor { get; private set; } = AppTheme.Brush(AppTheme.TextDim);
    public string RefreshText { get; private set; } = "";
    public IBrush BorderColor { get; private set; } = AppTheme.Brush(AppTheme.Hairline);

    public ProviderCardViewModel(ProviderId provider) => Provider = provider;

    public void Update(UsageSnapshot? snapshot, AttentionLevel attention, RefreshState refreshState, AppSettings settings)
    {
        BorderColor = attention == AttentionLevel.Normal
            ? AppTheme.Brush(AppTheme.Hairline)
            : new SolidColorBrush(AppTheme.AttentionColor(attention), 0.45);

        HealthBadgeText = snapshot?.Health.BadgeText() ?? "";
        HealthBadgeColor = AppTheme.Brush(snapshot?.Health switch
        {
            ProviderHealth.Ok => AppTheme.Ok,
            ProviderHealth.Degraded or ProviderHealth.ParseError => AppTheme.Warning,
            _ => AppTheme.TextDim,
        });

        RefreshText = refreshState switch
        {
            RefreshState.Refreshing => "syncing…",
            RefreshState.Success s => Format.Relative(s.Date),
            RefreshState.Failure f => $"failed {Format.Relative(f.Date)}",
            _ => "",
        };

        HasQuotaChip = snapshot?.QuotaStatus is Models.QuotaStatus.Blocked or Models.QuotaStatus.Warning;
        if (snapshot?.QuotaStatus == Models.QuotaStatus.Blocked)
        {
            QuotaChipText = "BLOCKED";
            QuotaChipColor = AppTheme.Brush(AppTheme.Danger);
        }
        else if (snapshot?.QuotaStatus == Models.QuotaStatus.Warning)
        {
            QuotaChipText = "NEAR LIMIT";
            QuotaChipColor = AppTheme.Brush(AppTheme.Warning);
        }

        if (snapshot is null || !snapshot.Health.IsUsable())
        {
            HasGauge = false;
            HeroText = snapshot?.Health.BadgeText() ?? "Waiting for data…";
            HasNote = snapshot?.Note is not null;
            NoteText = snapshot?.Note ?? "";
            HasReset = false;
            HasUsageLine = false;
            RaiseAll();
            return;
        }

        var metric = GaugeMetric.From(snapshot);
        if (metric is { } m)
        {
            HasGauge = true;
            var tint = AppTheme.RiskTint(m.Used, false, settings.WarningThresholdPercent, settings.CriticalThresholdPercent);
            HeroText = $"{Math.Round(m.Remaining)}%";
            HeroColor = AppTheme.Brush(tint);
            WindowLabel = m.IsWeekly ? "OF WEEKLY LIMIT LEFT" : "OF 5H SESSION LEFT";
            MeterPercent = m.Remaining;
            MeterColor = AppTheme.Brush(tint);

            var resets = m.IsWeekly ? snapshot.Weekly?.ResetsAt : snapshot.Session?.ResetsAt;
            HasReset = resets is not null;
            if (resets is { } r)
            {
                ResetLine = $"RESETS • {Format.Time(r)}";
                CountdownText = Format.Countdown(r);
            }

            var (tokens, cost) = m.IsWeekly
                ? (snapshot.Weekly?.Tokens.Total ?? 0, snapshot.Weekly?.Cost)
                : (snapshot.Session?.Tokens.Total ?? 0, snapshot.Session?.Cost);
            var parts = new List<string>();
            if (tokens > 0) parts.Add(Format.Tokens(tokens));
            if (cost?.AmountUsd is > 0.01) parts.Add("~" + Format.Usd(cost.AmountUsd));
            HasUsageLine = parts.Count > 0;
            UsageLine = string.Join(" · ", parts);
            HasNote = false;
        }
        else
        {
            // No official quota — show the "current window" fallback: current
            // session tokens + when it started, never the whole week's total.
            HasGauge = false;
            var tokens = snapshot.Session?.Tokens.Total is > 0 ? snapshot.Session!.Tokens.Total
                : snapshot.Weekly?.Tokens.Total is > 0 ? snapshot.Weekly!.Tokens.Total : (long?)null;
            HeroText = tokens is { } t ? Format.Tokens(t) : "—";
            HeroColor = AppTheme.Brush(AppTheme.TextPrimary);
            WindowLabel = "CURRENT SESSION · NO CAP REPORTED";
            HasReset = snapshot.Session?.StartedAt is not null;
            if (snapshot.Session?.StartedAt is { } started)
            {
                ResetLine = $"STARTED {Format.Relative(started)}";
                CountdownText = "";
            }
            HasUsageLine = snapshot.Session?.Cost?.AmountUsd is > 0.01;
            UsageLine = HasUsageLine ? "~" + Format.Usd(snapshot.Session!.Cost!.AmountUsd) : "";
            HasNote = snapshot.Note is not null;
            NoteText = snapshot.Note ?? "";
        }
        RaiseAll();
    }

    private void RaiseAll()
    {
        foreach (var prop in typeof(ProviderCardViewModel).GetProperties())
        {
            Raise(prop.Name);
        }
    }
}
