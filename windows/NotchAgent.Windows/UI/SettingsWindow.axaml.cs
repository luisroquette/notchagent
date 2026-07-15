using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Interactivity;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Services;

namespace NotchAgent.Windows.UI;

public partial class SettingsWindow : Window
{
    private readonly AppSettings _settings;
    private readonly Action _onChanged;
    private bool _loaded;

    public SettingsWindow(AppSettings settings, Action onChanged)
    {
        InitializeComponent();
        _settings = settings;
        _onChanged = onChanged;
        LoadFromSettings();
    }

    private void LoadFromSettings()
    {
        var themeCombo = this.FindControl<ComboBox>("ThemeCombo")!;
        themeCombo.SelectedIndex = (int)_settings.ThemeMode;

        this.FindControl<CheckBox>("LaunchAtLoginCheck")!.IsChecked = _settings.LaunchAtLogin;
        this.FindControl<CheckBox>("NotificationsCheck")!.IsChecked = _settings.NotificationsEnabled;
        this.FindControl<CheckBox>("RunnerCheck")!.IsChecked = _settings.RunnerEnabled;
        this.FindControl<CheckBox>("ProbeCheck")!.IsChecked = _settings.ClaudeQuotaProbeEnabled;

        this.FindControl<NumericUpDown>("IntervalUpDown")!.Value = (decimal)_settings.RefreshIntervalSeconds;
        this.FindControl<Slider>("WarningSlider")!.Value = _settings.WarningThresholdPercent;
        this.FindControl<Slider>("CriticalSlider")!.Value = _settings.CriticalThresholdPercent;
        UpdateLabels();
        _loaded = true;
    }

    private void UpdateLabels()
    {
        this.FindControl<TextBlock>("WarningLabel")!.Text = $"Warning at {_settings.WarningThresholdPercent:0}%";
        this.FindControl<TextBlock>("CriticalLabel")!.Text = $"Critical at {_settings.CriticalThresholdPercent:0}%";
    }

    private void OnThemeChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (!_loaded) return;
        _settings.ThemeMode = (ThemeMode)this.FindControl<ComboBox>("ThemeCombo")!.SelectedIndex;
        Save();
    }

    private void OnCheckToggled(object? sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        _settings.LaunchAtLogin = this.FindControl<CheckBox>("LaunchAtLoginCheck")!.IsChecked ?? false;
        _settings.NotificationsEnabled = this.FindControl<CheckBox>("NotificationsCheck")!.IsChecked ?? false;
        _settings.RunnerEnabled = this.FindControl<CheckBox>("RunnerCheck")!.IsChecked ?? false;
        _settings.ClaudeQuotaProbeEnabled = this.FindControl<CheckBox>("ProbeCheck")!.IsChecked ?? false;
        Save();
    }

    private void OnIntervalChanged(object? sender, NumericUpDownValueChangedEventArgs e)
    {
        if (!_loaded) return;
        _settings.RefreshIntervalSeconds = (double)(this.FindControl<NumericUpDown>("IntervalUpDown")!.Value ?? 60);
        Save();
    }

    private void OnWarningChanged(object? sender, RangeBaseValueChangedEventArgs e)
    {
        if (!_loaded) return;
        _settings.WarningThresholdPercent = this.FindControl<Slider>("WarningSlider")!.Value;
        if (_settings.CriticalThresholdPercent < _settings.WarningThresholdPercent + 5)
        {
            _settings.CriticalThresholdPercent = Math.Min(100, _settings.WarningThresholdPercent + 5);
            this.FindControl<Slider>("CriticalSlider")!.Value = _settings.CriticalThresholdPercent;
        }
        UpdateLabels();
        Save();
    }

    private void OnCriticalChanged(object? sender, RangeBaseValueChangedEventArgs e)
    {
        if (!_loaded) return;
        _settings.CriticalThresholdPercent = this.FindControl<Slider>("CriticalSlider")!.Value;
        if (_settings.WarningThresholdPercent > _settings.CriticalThresholdPercent - 5)
        {
            _settings.WarningThresholdPercent = Math.Max(40, _settings.CriticalThresholdPercent - 5);
            this.FindControl<Slider>("WarningSlider")!.Value = _settings.WarningThresholdPercent;
        }
        UpdateLabels();
        Save();
    }

    private void Save()
    {
        PreferencesStore.Save(_settings);
        _onChanged();
    }
}
