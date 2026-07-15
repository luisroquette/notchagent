namespace NotchAgent.Windows.Providers.Shared;

public static class AppPaths
{
    public static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// %APPDATA%\NotchAgent (created on first access).
    public static string AppSupport
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "NotchAgent");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }
}

public readonly record struct FileStamp(DateTimeOffset Modified, long Size)
{
    public static FileStamp? Of(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists) return null;
            return new FileStamp(info.LastWriteTimeUtc, info.Length);
        }
        catch (IOException)
        {
            return null;
        }
    }
}

public static class FileScan
{
    /// Recursively lists files with `ext`, modified after `cutoff`, newest first, capped.
    public static List<string> RecentFiles(string root, string ext, DateTimeOffset cutoff, int limit = 500)
    {
        if (!Directory.Exists(root)) return new List<string>();
        var results = new List<(string Path, DateTimeOffset Modified)>();
        foreach (var file in Directory.EnumerateFiles(root, $"*.{ext}", SearchOption.AllDirectories))
        {
            DateTimeOffset modified;
            try { modified = File.GetLastWriteTimeUtc(file); }
            catch (IOException) { continue; }
            if (modified >= cutoff)
            {
                results.Add((file, modified));
            }
        }
        return results
            .OrderByDescending(r => r.Modified)
            .Take(limit)
            .Select(r => r.Path)
            .ToList();
    }
}
