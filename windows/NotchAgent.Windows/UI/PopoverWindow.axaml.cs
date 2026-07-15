using Avalonia;
using Avalonia.Controls;
using Avalonia.Threading;
using NotchAgent.Windows.Services;

namespace NotchAgent.Windows.UI;

public partial class PopoverWindow : Window
{
    private readonly PopoverViewModel _viewModel;
    private readonly UsageStore _store;
    private readonly RefreshScheduler _scheduler;
    private readonly Action _openSettings;
    private readonly DispatcherTimer _tick;

    public PopoverWindow(UsageStore store, RefreshScheduler scheduler, Action openSettings)
    {
        InitializeComponent();
        _store = store;
        _scheduler = scheduler;
        _openSettings = openSettings;
        _viewModel = new PopoverViewModel(store);
        DataContext = _viewModel;

        // Refresh countdown/relative-time text even when nothing else changes.
        _tick = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        _tick.Tick += (_, _) => _viewModel.Refresh();
        _tick.Start();
    }

    /// Positions near the system tray (bottom-right of the working area,
    /// matching how Windows flyouts anchor to the tray).
    public void ShowNearTray()
    {
        var screen = Screens.Primary ?? Screens.All.FirstOrDefault();
        if (screen is not null)
        {
            var area = screen.WorkingArea;
            Position = new PixelPoint(
                area.Right - (int)Width - 12,
                area.Bottom - (int)Height - 12);
        }
        Show();
        Activate();
    }

    protected override void OnLostFocus(Avalonia.Interactivity.RoutedEventArgs e)
    {
        base.OnLostFocus(e);
        Hide();
    }

    private void OnRefreshClick(object? sender, Avalonia.Interactivity.RoutedEventArgs e) => _scheduler.RefreshNow();

    private void OnPauseClick(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        _store.IsPaused = !_store.IsPaused;
        _store.Record(new Models.UsageEvent
        {
            Kind = Models.UsageEvent.EventKind.Info,
            Message = _store.IsPaused ? "Refresh paused" : "Refresh resumed",
        });
        _viewModel.Refresh();
    }

    private void OnSettingsClick(object? sender, Avalonia.Interactivity.RoutedEventArgs e) => _openSettings();

    private void OnQuitClick(object? sender, Avalonia.Interactivity.RoutedEventArgs e) =>
        (Avalonia.Application.Current?.ApplicationLifetime as Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime)?.Shutdown();
}
