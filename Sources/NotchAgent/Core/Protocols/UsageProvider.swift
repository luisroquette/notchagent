import Foundation

/// Plugin surface for provider integrations. Implementations must be cheap to
/// construct, do all heavy I/O inside `fetchSnapshot`, and never throw for
/// "no data" situations — encode those in `UsageSnapshot.health` instead.
/// Throwing is reserved for unexpected failures worth logging as errors.
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: ProviderCapabilities { get }

    func detectInstallation() -> ProviderInstallation
    func fetchSnapshot(settings: AppSettings) async throws -> UsageSnapshot
}
