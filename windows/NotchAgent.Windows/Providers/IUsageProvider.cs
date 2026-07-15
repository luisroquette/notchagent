using NotchAgent.Windows.Models;

namespace NotchAgent.Windows.Providers;

public enum ProviderInstallationKind { Installed, NotInstalled }

public readonly record struct ProviderInstallation(ProviderInstallationKind Kind, string? DataPath = null)
{
    public static ProviderInstallation NotInstalled => new(ProviderInstallationKind.NotInstalled);
    public static ProviderInstallation Installed(string path) => new(ProviderInstallationKind.Installed, path);
}

/// Plugin surface for provider integrations. Implementations must be cheap to
/// construct, do all heavy I/O inside FetchSnapshotAsync, and never throw for
/// "no data" situations — encode those in UsageSnapshot.Health instead.
public interface IUsageProvider
{
    ProviderId Id { get; }
    ProviderInstallation DetectInstallation();
    Task<UsageSnapshot> FetchSnapshotAsync(AppSettings settings, CancellationToken ct);
}
