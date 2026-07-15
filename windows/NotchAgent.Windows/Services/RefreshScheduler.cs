using Avalonia.Threading;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Providers;

namespace NotchAgent.Windows.Services;

/// Central refresh loop: fans out to all providers concurrently, feeds the
/// store, persists snapshots. One scheduler owns all polling — no provider
/// ever refreshes itself.
public sealed class RefreshScheduler
{
    private readonly List<IUsageProvider> _providers;
    private readonly UsageStore _store;
    private readonly SnapshotStore _snapshotStore;
    private CancellationTokenSource? _loopCts;
    private bool _tickInFlight;

    public RefreshScheduler(List<IUsageProvider> providers, UsageStore store, SnapshotStore snapshotStore)
    {
        _providers = providers;
        _store = store;
        _snapshotStore = snapshotStore;
    }

    public void Start()
    {
        if (_loopCts is not null) return;
        Log.Refresh.LogInformation("scheduler started");
        var cts = new CancellationTokenSource();
        _loopCts = cts;
        _ = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                try { await Tick(cts.Token); }
                catch (Exception ex)
                {
                    // Defense in depth: Tick() already catches internally, but
                    // the loop itself must survive anything that slips through.
                    Log.Refresh.LogError("scheduler loop caught: {0}", ex);
                }
                var interval = Math.Max(15, _store.Settings.RefreshIntervalSeconds);
                try { await Task.Delay(TimeSpan.FromSeconds(interval), cts.Token); }
                catch (TaskCanceledException) { return; }
            }
        }, cts.Token);
    }

    public void Stop()
    {
        _loopCts?.Cancel();
        _loopCts = null;
    }

    /// Stop + start: applies a changed refresh interval immediately instead
    /// of waiting out the previous (possibly long) sleep.
    public void Restart()
    {
        Stop();
        Start();
    }

    public void RefreshNow()
    {
        _ = Task.Run(() => Tick(CancellationToken.None, force: true));
    }

    private async Task Tick(CancellationToken ct, bool force = false)
    {
        if (_store.IsPaused && !force) return;
        // A forced tick may race the periodic loop — never run two interleaved.
        if (_tickInFlight) return;
        _tickInFlight = true;
        try
        {
            var settings = _store.Settings;

            // UsageStore mutations synchronously raise PropertyChanged, which
            // ViewModels handle by constructing Avalonia brushes/colors —
            // Avalonia objects can only be created on the UI thread, so every
            // store mutation must be dispatched there even though this whole
            // method runs on a background Task (the actual file/network I/O
            // below stays off-thread; only the store touches are marshaled).
            await Dispatcher.UIThread.InvokeAsync(() =>
            {
                foreach (var provider in _providers) _store.MarkRefreshing(provider.Id);
            });

            var tasks = _providers.Select(async provider =>
            {
                try
                {
                    var snapshot = await provider.FetchSnapshotAsync(settings, ct);
                    return (provider.Id, Snapshot: (UsageSnapshot?)snapshot, Error: (string?)null);
                }
                catch (Exception ex)
                {
                    return (provider.Id, Snapshot: (UsageSnapshot?)null, Error: ex.Message);
                }
            });
            var results = await Task.WhenAll(tasks);

            await Dispatcher.UIThread.InvokeAsync(() =>
            {
                foreach (var (id, snapshot, error) in results)
                {
                    if (snapshot is not null)
                    {
                        _store.Apply(snapshot);
                        Log.Refresh.LogDebug("refreshed {0}: {1}", id, snapshot.Health);
                    }
                    else
                    {
                        _store.ApplyFailure(id, error ?? "unknown error");
                        Log.Refresh.LogError("refresh failed {0}: {1}", id, error ?? "unknown error");
                    }
                }
            });
            _snapshotStore.Save(_store.Snapshots);
        }
        catch (Exception ex)
        {
            // A single bad tick (e.g. a transient file lock) must never kill
            // the loop silently — `_ = Task.Run(...)` in Start() discards the
            // task, so an uncaught exception here would stop all future
            // refreshes forever with no visible error until the app restarts.
            Log.Refresh.LogError("tick failed: {0}", ex);
        }
        finally
        {
            _tickInFlight = false;
        }
    }
}
