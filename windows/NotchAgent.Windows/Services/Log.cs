using System.Diagnostics;

namespace NotchAgent.Windows.Services;

/// Minimal categorized logger — Debug.WriteLine is enough for a tray app;
/// no need to pull in Microsoft.Extensions.Logging for this scope. Use
/// numbered placeholders ({0}, {1}, ...) like string.Format.
public sealed class Logger
{
    private readonly string _category;
    internal Logger(string category) => _category = category;

    public void LogInformation(string message, params object?[] args) => Write("info", message, args);
    public void LogDebug(string message, params object?[] args) => Write("debug", message, args);
    public void LogError(string message, params object?[] args) => Write("error", message, args);

    private void Write(string level, string message, object?[] args)
    {
        var formatted = args.Length > 0 ? string.Format(message, args) : message;
        var line = $"[{_category}:{level}] {formatted}";
        Debug.WriteLine(line);
        // Debug.WriteLine needs an attached debugger to show anywhere — also
        // write to the console so `dotnet run` from a terminal is diagnosable.
        Console.WriteLine(line);
    }
}

public static class Log
{
    public static readonly Logger App = new("app");
    public static readonly Logger Notch = new("notch");
    public static readonly Logger Refresh = new("refresh");
    public static readonly Logger Providers = new("providers");
    public static readonly Logger Persistence = new("persistence");
}
