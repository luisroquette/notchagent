using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Styling;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Providers;
using NotchAgent.Windows.Providers.Claude;
using NotchAgent.Windows.Providers.Codex;
using NotchAgent.Windows.Services;
using NotchAgent.Windows.UI;

namespace NotchAgent.Windows;

/// Composition root: builds and wires every service exactly once, sets up
/// the tray icon, and owns the popover/settings windows — the .NET analogue
/// of the Mac app's AppEnvironment.
public partial class App : Application
{
    private AppSettings _settings = null!;
    private UsageStore _store = null!;
    private RefreshScheduler _scheduler = null!;
    private SnapshotStore _snapshotStore = null!;
    private TrayIcon _trayIcon = null!;
    private PopoverWindow? _popover;
    private SettingsWindow? _settingsWindow;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;

            _settings = PreferencesStore.Load();
            _store = new UsageStore(_settings);
            _snapshotStore = new SnapshotStore();

            var providers = new List<IUsageProvider> { new ClaudeProvider(), new CodexProvider() };
            _scheduler = new RefreshScheduler(providers, _store, _snapshotStore);

            ApplyTheme();

            _trayIcon = new TrayIcon
            {
                Icon = TrayIconFactory.Create(AppTheme.Ok),
                ToolTipText = "NotchAgent",
            };
            _trayIcon.Clicked += (_, _) => TogglePopover();
            var icons = new TrayIcons { _trayIcon };
            TrayIcon.SetIcons(this, icons);

            _store.PropertyChanged += (_, _) => UpdateTrayIcon();

            var persisted = _snapshotStore.Load();
            _store.Restore(persisted);
            _store.Record(new UsageEvent { Kind = UsageEvent.EventKind.Info, Message = "NotchAgent started" });
            _scheduler.Start();
        }

        base.OnFrameworkInitializationCompleted();
    }

    private void TogglePopover()
    {
        _popover ??= new PopoverWindow(_store, _scheduler, OpenSettings);
        if (_popover.IsVisible) _popover.Hide();
        else _popover.ShowNearTray();
    }

    private void OpenSettings()
    {
        if (_settingsWindow is null)
        {
            _settingsWindow = new SettingsWindow(_settings, OnSettingsChanged);
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    private void OnSettingsChanged()
    {
        ApplyTheme();
        _scheduler.Restart();
    }

    private void ApplyTheme()
    {
        RequestedThemeVariant = _settings.ThemeMode switch
        {
            ThemeMode.Dark => ThemeVariant.Dark,
            ThemeMode.Light => ThemeVariant.Light,
            _ => ThemeVariant.Default,
        };
    }

    private void UpdateTrayIcon()
    {
        var color = AppTheme.AttentionColor(_store.OverallAttention);
        _trayIcon.Icon = TrayIconFactory.Create(color);
    }
}
