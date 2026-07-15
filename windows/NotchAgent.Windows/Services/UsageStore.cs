using System.ComponentModel;
using System.Runtime.CompilerServices;
using NotchAgent.Windows.Models;

namespace NotchAgent.Windows.Services;

public abstract record RefreshState
{
    public sealed record Idle : RefreshState;
    public sealed record Refreshing : RefreshState;
    public sealed record Success(DateTimeOffset Date) : RefreshState;
    public sealed record Failure(DateTimeOffset Date, string Error) : RefreshState;

    public static readonly RefreshState IdleValue = new Idle();
}

public sealed record PercentSample(DateTimeOffset Date, double Percent);

/// Single source of truth for the UI. Raises PropertyChanged so WPF/Avalonia
/// bindings update automatically — the .NET analogue of the Mac app's
/// @Observable UsageStore.
public sealed class UsageStore : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public Dictionary<ProviderId, UsageSnapshot> Snapshots { get; } = new();
    public Dictionary<ProviderId, RefreshState> RefreshStates { get; } = new();
    public List<UsageEvent> Events { get; } = new();
    private const int MaxEvents = 200;

    private readonly Dictionary<ProviderId, List<PercentSample>> _percentHistory = new();
    private readonly Dictionary<string, HashSet<int>> _firedThresholds = new();
    private readonly Dictionary<ProviderId, bool> _wasBlocked = new();
    private CancellationTokenSource? _alertDismissCts;
    private CancellationTokenSource? _restoreDismissCts;

    public AppSettings Settings { get; }
    public bool IsPaused { get; set; }

    public event Action<ProviderId, AttentionLevel, string>? OnAlert;
    public event Action<RestoreMoment>? OnRestore;

    private ThresholdAlert? _activeThresholdAlert;
    public ThresholdAlert? ActiveThresholdAlert
    {
        get => _activeThresholdAlert;
        private set { _activeThresholdAlert = value; Raise(); }
    }

    private RestoreMoment? _activeRestoreMoment;
    public RestoreMoment? ActiveRestoreMoment
    {
        get => _activeRestoreMoment;
        private set { _activeRestoreMoment = value; Raise(); }
    }

    public string? ActiveIncident { get; private set; }

    public UsageStore(AppSettings settings)
    {
        Settings = settings;
    }

    public AttentionLevel Attention(ProviderId provider) =>
        Snapshots.TryGetValue(provider, out var s) ? StatusAggregator.Attention(s, Settings) : AttentionLevel.Normal;

    public AttentionLevel OverallAttention => StatusAggregator.OverallAttention(Snapshots.Values, Settings);

    public void Restore(Dictionary<ProviderId, UsageSnapshot> persisted)
    {
        foreach (var (provider, snapshot) in persisted)
        {
            if (!Snapshots.ContainsKey(provider)) Snapshots[provider] = snapshot;
        }
        Raise(nameof(Snapshots));
    }

    public void MarkRefreshing(ProviderId provider)
    {
        RefreshStates[provider] = new RefreshState.Refreshing();
        Raise(nameof(RefreshStates));
    }

    public void Apply(UsageSnapshot snapshot)
    {
        var alerts = StatusAggregator.TransitionAlerts(Snapshots, snapshot, Settings);
        Snapshots[snapshot.Provider] = snapshot;
        RefreshStates[snapshot.Provider] = new RefreshState.Success(snapshot.CapturedAt);

        if (snapshot.Session?.UsedPercent is { } percent)
        {
            var samples = _percentHistory.GetValueOrDefault(snapshot.Provider) ?? new List<PercentSample>();
            samples.Add(new PercentSample(snapshot.CapturedAt, percent));
            var cutoff = DateTimeOffset.UtcNow - TimeSpan.FromHours(6);
            samples.RemoveAll(s => s.Date < cutoff);
            _percentHistory[snapshot.Provider] = samples;
        }

        ProcessThresholds(snapshot);
        ProcessRecovery(snapshot);

        foreach (var alert in alerts)
        {
            Record(new UsageEvent { Provider = alert.Provider, Kind = UsageEvent.EventKind.Alert, Level = alert.Level, Message = alert.Message });
            OnAlert?.Invoke(alert.Provider, alert.Level, alert.Message);
        }
        Raise(nameof(Snapshots));
    }

    public void ApplyFailure(ProviderId provider, string error)
    {
        RefreshStates[provider] = new RefreshState.Failure(DateTimeOffset.UtcNow, error);
        Record(new UsageEvent { Provider = provider, Kind = UsageEvent.EventKind.Error, Level = AttentionLevel.Warning, Message = error });
        Raise(nameof(RefreshStates));
    }

    public void Record(UsageEvent evt)
    {
        Events.Insert(0, evt);
        if (Events.Count > MaxEvents) Events.RemoveRange(MaxEvents, Events.Count - MaxEvents);
        Raise(nameof(Events));
    }

    private void ProcessThresholds(UsageSnapshot snapshot)
    {
        // A transient snapshot without a gauge keeps the fired sets intact —
        // resetting here would re-fire (and re-notify) already-seen crossings.
        if (GaugeMetric.From(snapshot) is not { } metric) return;
        var remaining = metric.Remaining;
        var key = $"{snapshot.Provider}·{(metric.IsWeekly ? "wk" : "5h")}";
        var fired = _firedThresholds.GetValueOrDefault(key) ?? new HashSet<int>();

        if (ThresholdAlerts.ShouldReset(remaining))
        {
            fired = new HashSet<int>();
            if (ActiveThresholdAlert?.Provider == snapshot.Provider) DismissThresholdAlert();
        }
        if (ThresholdAlerts.NewCrossing(remaining, fired) is { } threshold)
        {
            fired.UnionWith(ThresholdAlerts.Crossed(remaining));
            var alert = new ThresholdAlert(snapshot.Provider, threshold, remaining, metric.IsWeekly);
            Present(alert);
            var level = ThresholdAlerts.AttentionLevel(threshold);
            var message = ThresholdAlerts.Message(alert);
            Record(new UsageEvent { Provider = snapshot.Provider, Kind = UsageEvent.EventKind.Alert, Level = level, Message = message });
            OnAlert?.Invoke(snapshot.Provider, level, message);
        }
        _firedThresholds[key] = fired;
    }

    /// Severity-aware takeover: a sticky 5% moment is never replaced by a
    /// milder crossing from another provider in the same refresh cycle.
    private void Present(ThresholdAlert alert)
    {
        if (ActiveThresholdAlert is { } current && current.Threshold < alert.Threshold) return;
        ActiveThresholdAlert = alert;
        _alertDismissCts?.Cancel();
        if (alert.Threshold <= 5) return;
        var cts = new CancellationTokenSource();
        _alertDismissCts = cts;
        _ = Task.Run(async () =>
        {
            try { await Task.Delay(TimeSpan.FromSeconds(4.5), cts.Token); }
            catch (TaskCanceledException) { return; }
            if (ActiveThresholdAlert == alert) DismissThresholdAlert();
        });
    }

    public void DismissThresholdAlert()
    {
        _alertDismissCts?.Cancel();
        _alertDismissCts = null;
        ActiveThresholdAlert = null;
    }

    /// Detects the blocked → usable transition and celebrates it — but only
    /// when the user could plausibly have felt it: recent activity around
    /// the unblock, not "picked the PC up three days later."
    private void ProcessRecovery(UsageSnapshot snapshot)
    {
        var isBlockedNow = snapshot.QuotaStatus == Models.QuotaStatus.Blocked;
        var wasBlockedBefore = _wasBlocked.GetValueOrDefault(snapshot.Provider);
        _wasBlocked[snapshot.Provider] = isBlockedNow;
        if (!wasBlockedBefore || isBlockedNow) return;
        if (snapshot.LastActivityAt is not { } lastActivity ||
            (snapshot.CapturedAt - lastActivity) >= TimeSpan.FromMinutes(10)) return;

        var metric = GaugeMetric.From(snapshot);
        var moment = new RestoreMoment(snapshot.Provider, metric?.Remaining ?? 100, metric?.IsWeekly ?? false);
        ActiveRestoreMoment = moment;
        _restoreDismissCts?.Cancel();
        var cts = new CancellationTokenSource();
        _restoreDismissCts = cts;
        _ = Task.Run(async () =>
        {
            try { await Task.Delay(TimeSpan.FromSeconds(3.5), cts.Token); }
            catch (TaskCanceledException) { return; }
            if (ActiveRestoreMoment == moment) DismissRestoreMoment();
        });
        Record(new UsageEvent { Provider = snapshot.Provider, Kind = UsageEvent.EventKind.Info, Message = moment.Message });
        OnRestore?.Invoke(moment);
    }

    public void DismissRestoreMoment()
    {
        _restoreDismissCts?.Cancel();
        _restoreDismissCts = null;
        ActiveRestoreMoment = null;
    }

    public void SetIncident(string? incident)
    {
        if (incident == ActiveIncident) return;
        ActiveIncident = incident;
        Record(new UsageEvent
        {
            Kind = UsageEvent.EventKind.Info,
            Level = incident is not null ? AttentionLevel.Warning : AttentionLevel.Normal,
            Message = incident is not null ? $"Anthropic incident: {incident}" : "Anthropic incident resolved",
        });
        Raise(nameof(ActiveIncident));
    }
}
