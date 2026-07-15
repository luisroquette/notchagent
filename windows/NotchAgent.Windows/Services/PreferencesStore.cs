using System.Text.Json;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Providers.Shared;

namespace NotchAgent.Windows.Services;

public static class PreferencesStore
{
    private static string Path => System.IO.Path.Combine(AppPaths.AppSupport, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (!File.Exists(Path)) return new AppSettings();
            var json = File.ReadAllText(Path);
            return JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();
        }
        catch (Exception ex) when (ex is IOException or JsonException)
        {
            return new AppSettings();
        }
    }

    public static void Save(AppSettings settings)
    {
        try
        {
            File.WriteAllText(Path, JsonSerializer.Serialize(settings));
        }
        catch (IOException ex)
        {
            Log.Persistence.LogError("settings save failed: {0}", ex.Message);
        }
    }
}
