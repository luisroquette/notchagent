using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Threading;
using NotchAgent.Windows.Services;

namespace NotchAgent.Windows.UI;

/// The Windows equivalent of the Mac notch overlay: a small, always-on-top
/// bar docked to the top of the primary screen. Compact by default, expands
/// on hover, pins open on click, and gets out of the way of fullscreen apps
/// (games, video, presentations) the way Discord/NVIDIA overlays do.
public partial class FloatingBarWindow : Window
{
    private readonly BarViewModel _viewModel;
    private readonly UsageStore _store;
    private readonly RefreshScheduler _scheduler;
    private readonly Action _openSettings;
    private readonly DispatcherTimer _refreshTextTick;
    private readonly DispatcherTimer _fullscreenTick;

    private bool _isExpanded;
    private bool _isPinned;
    private bool _hiddenForFullscreen;
    private CancellationTokenSource? _hoverCts;

    public FloatingBarWindow(UsageStore store, RefreshScheduler scheduler, Action openSettings)
    {
        InitializeComponent();
        _store = store;
        _scheduler = scheduler;
        _openSettings = openSettings;
        _viewModel = new BarViewModel(store);
        DataContext = _viewModel;

        var chassis = this.FindControl<Border>("Chassis")!;
        chassis.PointerEntered += (_, _) => HoverChanged(true);
        chassis.PointerExited += (_, _) => HoverChanged(false);
        LayoutUpdated += (_, _) => RepositionTopCenter();

        // Relative-time text ("updated 2m ago") drifts even without a refresh.
        _refreshTextTick = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        _refreshTextTick.Tick += (_, _) => _viewModel.Refresh();
        _refreshTextTick.Start();

        _fullscreenTick = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        _fullscreenTick.Tick += (_, _) => CheckFullscreen();
        _fullscreenTick.Start();
    }

    public void Launch()
    {
        Show();
        RepositionTopCenter();
    }

    /// Cancels any fullscreen auto-hide and brings the bar back — used by the
    /// tray icon's click/menu so the user always has a way back if it's gone.
    public void ForceShow()
    {
        _hiddenForFullscreen = false;
        if (!IsVisible) Show();
        RepositionTopCenter();
    }

    private void CheckFullscreen()
    {
        var fullscreen = FullscreenDetector.IsForegroundFullscreen();
        if (fullscreen && !_hiddenForFullscreen)
        {
            _hiddenForFullscreen = true;
            Hide();
        }
        else if (!fullscreen && _hiddenForFullscreen)
        {
            _hiddenForFullscreen = false;
            Show();
            RepositionTopCenter();
        }
    }

    private void RepositionTopCenter()
    {
        var screen = Screens.ScreenFromWindow(this) ?? Screens.Primary ?? Screens.All.FirstOrDefault();
        if (screen is null) return;
        var bounds = screen.Bounds;
        var width = (int)Math.Max(Bounds.Width, 1);
        Position = new PixelPoint(bounds.X + (bounds.Width - width) / 2, bounds.Y);
    }

    /// Debounced like a real hover affordance: a brief pause before expanding
    /// (so passing the mouse over doesn't flicker it open) and a longer pause
    /// before collapsing (so moving toward a button doesn't close it first).
    private void HoverChanged(bool hovering)
    {
        _hoverCts?.Cancel();
        var cts = new CancellationTokenSource();
        _hoverCts = cts;
        var delay = hovering ? TimeSpan.FromMilliseconds(120) : TimeSpan.FromMilliseconds(400);

        _ = Task.Run(async () =>
        {
            try { await Task.Delay(delay, cts.Token); }
            catch (TaskCanceledException) { return; }
            if (cts.Token.IsCancellationRequested) return;
            Dispatcher.UIThread.Post(() =>
            {
                if (hovering) SetExpanded(true);
                else if (!_isPinned) SetExpanded(false);
            });
        });
    }

    private void SetExpanded(bool expanded)
    {
        if (_isExpanded == expanded) return;
        _isExpanded = expanded;
        this.FindControl<CompactBarView>("CompactPanel")!.IsVisible = !expanded;
        this.FindControl<DockPanel>("ExpandedPanel")!.IsVisible = expanded;
    }

    private void OnCompactClicked(object? sender, PointerPressedEventArgs e)
    {
        _isPinned = !_isPinned;
        SetExpanded(_isPinned || _isExpanded);
    }

    private void OnRefreshClick(object? sender, RoutedEventArgs e) => _scheduler.RefreshNow();

    private void OnPauseClick(object? sender, RoutedEventArgs e)
    {
        _store.IsPaused = !_store.IsPaused;
        _store.Record(new Models.UsageEvent
        {
            Kind = Models.UsageEvent.EventKind.Info,
            Message = _store.IsPaused ? "Refresh paused" : "Refresh resumed",
        });
        _viewModel.Refresh();
    }

    private void OnSettingsClick(object? sender, RoutedEventArgs e) => _openSettings();

    private void OnQuitClick(object? sender, RoutedEventArgs e) =>
        (Avalonia.Application.Current?.ApplicationLifetime as Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime)?.Shutdown();
}
