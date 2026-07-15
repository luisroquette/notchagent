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
/// the tray icon (secondary access) and the always-on floating bar (the
/// primary, notch-like UI) — the .NET analogue of the Mac app's AppEnvironment.
public partial class App : Application
{
    private AppSettings _settings = null!;
    private UsageStore _store = null!;
    private RefreshScheduler _scheduler = null!;
    private SnapshotStore _snapshotStore = null!;
    private TrayIcon _trayIcon = null!;
    private NativeMenuItem _pauseMenuItem = null!;
    private FloatingBarWindow _bar = null!;
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
            SetupTrayIcon(desktop);

            _bar = new FloatingBarWindow(_store, _scheduler, OpenSettings);
            _bar.Launch();

            _store.PropertyChanged += (_, _) => UpdateTrayIcon();

            var persisted = _snapshotStore.Load();
            _store.Restore(persisted);
            _store.Record(new UsageEvent { Kind = UsageEvent.EventKind.Info, Message = "NotchAgent started" });
            _scheduler.Start();
        }

        base.OnFrameworkInitializationCompleted();
    }

    /// The tray icon is secondary now — the floating bar is the primary,
    /// always-visible surface. Left-click brings the bar back if a fullscreen
    /// app auto-hid it; right-click (the OS default for TrayIcon.Menu) offers
    /// the same quick actions the bar's footer has.
    private void SetupTrayIcon(IClassicDesktopStyleApplicationLifetime desktop)
    {
        var menu = new NativeMenu();

        var refreshItem = new NativeMenuItem("Refresh Now");
        refreshItem.Click += (_, _) => _scheduler.RefreshNow();
        menu.Add(refreshItem);

        _pauseMenuItem = new NativeMenuItem(_store.IsPaused ? "Resume" : "Pause");
        _pauseMenuItem.Click += (_, _) =>
        {
            _store.IsPaused = !_store.IsPaused;
            _pauseMenuItem.Header = _store.IsPaused ? "Resume" : "Pause";
        };
        menu.Add(_pauseMenuItem);

        menu.Add(new NativeMenuItemSeparator());

        var showBarItem = new NativeMenuItem("Show Bar");
        showBarItem.Click += (_, _) => _bar.ForceShow();
        menu.Add(showBarItem);

        var settingsItem = new NativeMenuItem("Settings…");
        settingsItem.Click += (_, _) => OpenSettings();
        menu.Add(settingsItem);

        menu.Add(new NativeMenuItemSeparator());

        var quitItem = new NativeMenuItem("Quit");
        quitItem.Click += (_, _) => desktop.Shutdown();
        menu.Add(quitItem);

        _trayIcon = new TrayIcon
        {
            Icon = TrayIconFactory.Create(AppTheme.Ok),
            ToolTipText = "NotchAgent",
            Menu = menu,
        };
        _trayIcon.Clicked += (_, _) => _bar.ForceShow();
        TrayIcon.SetIcons(this, new TrayIcons { _trayIcon });
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
