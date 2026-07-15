using System.Text.Json;
using NotchAgent.Windows.Models;
using NotchAgent.Windows.Providers.Shared;

namespace NotchAgent.Windows.Services;

/// Persists the last valid snapshot per provider so the UI has data instantly
/// on launch, before the first refresh completes.
public sealed class SnapshotStore
{
    private readonly string _path;
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = false };

    public SnapshotStore(string? path = null)
    {
        _path = path ?? Path.Combine(AppPaths.AppSupport, "snapshots.json");
    }

    public Dictionary<ProviderId, UsageSnapshot> Load()
    {
        try
        {
            if (!File.Exists(_path)) return new();
            var json = File.ReadAllText(_path);
            return JsonSerializer.Deserialize<Dictionary<ProviderId, UsageSnapshot>>(json, JsonOptions) ?? new();
        }
        catch (Exception ex) when (ex is IOException or JsonException)
        {
            return new();
        }
    }

    public void Save(Dictionary<ProviderId, UsageSnapshot> snapshots)
    {
        try
        {
            var json = JsonSerializer.Serialize(snapshots, JsonOptions);
            var tmp = _path + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, _path, overwrite: true);
        }
        catch (IOException ex)
        {
            Log.Persistence.LogError("snapshot save failed: {0}", ex.Message);
        }
    }
}
