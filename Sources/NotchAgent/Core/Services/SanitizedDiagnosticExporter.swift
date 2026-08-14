import Foundation

struct SanitizedDiagnosticReport: Codable, Sendable {
    struct DeskRecord: Codable, Sendable {
        var phase: NotchAgentDeskConnectionState.Phase
        var firmwareVersion: String?
        var protocolMajor: UInt8?
        var protocolMinor: UInt8?
        var uptimeSeconds: UInt64?
        var freeHeapBytes: UInt32?
        var minimumFreeHeapBytes: UInt32?
        var framesPerSecond: Double?
        var resetReason: String?
        var invalidFrameCount: UInt32?
        var handshakeCount: UInt32?
        var touchCount: UInt32?
        var touchInterruptCount: UInt32?
        var touchReadErrorCount: UInt32?
        var touchPollAttemptCount: UInt32?
        var touchPollTouchCount: UInt32?
        var touchControllerPresent: Bool?
        var lastTouchLatencyMs: Double?
        var maximumTouchLatencyMs: Double?
    }

    struct ProviderRecord: Codable, Sendable {
        var provider: ProviderID
        var health: ProviderHealth?
        var capturedAt: Date?
        var refreshState: String
    }

    struct AccountRecord: Codable, Sendable {
        var service: APIServiceID
        var readStatus: APIAccountReadStatus
        var auditOutcome: APIAccountAuditOutcome
        var sources: [APIAccountDataOrigin]
        var spendPeriod: APIAccountSpendPeriod?
        var capturedAt: Date?
        var hasSpend: Bool
        var hasBalance: Bool
        var hasRecharge: Bool
        var hasPlan: Bool
        var hasQuota: Bool
        var findings: [String]
    }

    var schemaVersion: Int
    var generatedAt: Date
    var appVersion: String
    var configuredAPIAccountCount: Int
    var providers: [ProviderRecord]
    var accounts: [AccountRecord]
    var desk: DeskRecord?
}

enum SanitizedDiagnosticExporter {
    @MainActor
    static func report(
        settings: AppSettings,
        snapshots: [ProviderID: UsageSnapshot],
        refreshStates: [ProviderID: RefreshState],
        deskConnection: NotchAgentDeskConnectionState? = nil,
        generatedAt: Date = Date(),
        bundle: Bundle = .main
    ) -> SanitizedDiagnosticReport {
        let accounts = settings.apiAccounts.filter { $0.enabled && !$0.service.isSubscriptionService }
        let usages = snapshots[.apiAccounts]?.accountUsage ?? []
        let usagesByID = Dictionary(uniqueKeysWithValues: usages.map { ($0.accountID, $0) })
        let audits = APIAccountIntegrityAuditor.audit(accounts: accounts, usages: usages)
        let auditByID = Dictionary(uniqueKeysWithValues: audits.map { ($0.accountID, $0) })

        let providerRecords = ProviderID.allCases.map { provider in
            SanitizedDiagnosticReport.ProviderRecord(
                provider: provider,
                health: snapshots[provider]?.health,
                capturedAt: snapshots[provider]?.capturedAt,
                refreshState: refreshStateLabel(refreshStates[provider] ?? .idle)
            )
        }
        let accountRecords = accounts.compactMap { account -> SanitizedDiagnosticReport.AccountRecord? in
            guard let audit = auditByID[account.id] else { return nil }
            let usage = usagesByID[account.id]
            return SanitizedDiagnosticReport.AccountRecord(
                service: account.service,
                readStatus: audit.readStatus,
                auditOutcome: audit.outcome,
                sources: audit.sources,
                spendPeriod: audit.spendPeriod,
                capturedAt: usage?.capturedAt,
                hasSpend: usage?.monthlySpendUSD != nil || usage?.monthlySpendBRL != nil,
                hasBalance: usage?.balanceUSD != nil || usage?.balanceBRL != nil,
                hasRecharge: usage?.rechargeUSD != nil || usage?.rechargeBRL != nil,
                hasPlan: usage?.monthlyPlanUSD != nil || usage?.monthlyPlanBRL != nil,
                hasQuota: usage?.cycleUsed != nil || usage?.cycleLimit != nil,
                findings: audit.findings
            )
        }

        return SanitizedDiagnosticReport(
            schemaVersion: 4,
            generatedAt: generatedAt,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            configuredAPIAccountCount: accounts.count,
            providers: providerRecords,
            accounts: accountRecords,
            desk: deskConnection.map {
                SanitizedDiagnosticReport.DeskRecord(
                    phase: $0.phase,
                    firmwareVersion: $0.firmwareVersion,
                    protocolMajor: $0.protocolMajor,
                    protocolMinor: $0.protocolMinor,
                    uptimeSeconds: $0.telemetry?.uptimeSeconds,
                    freeHeapBytes: $0.telemetry?.freeHeapBytes,
                    minimumFreeHeapBytes: $0.telemetry?.minimumFreeHeapBytes,
                    framesPerSecond: $0.telemetry?.framesPerSecond,
                    resetReason: $0.telemetry?.resetReason,
                    invalidFrameCount: $0.telemetry?.invalidFrameCount,
                    handshakeCount: $0.telemetry?.handshakeCount,
                    touchCount: $0.telemetry?.touchCount,
                    touchInterruptCount: $0.telemetry?.touchInterruptCount,
                    touchReadErrorCount: $0.telemetry?.touchReadErrorCount,
                    touchPollAttemptCount: $0.telemetry?.touchPollAttemptCount,
                    touchPollTouchCount: $0.telemetry?.touchPollTouchCount,
                    touchControllerPresent: $0.telemetry?.touchControllerPresent,
                    lastTouchLatencyMs: $0.telemetry?.lastTouchLatencyMs,
                    maximumTouchLatencyMs: $0.telemetry?.maximumTouchLatencyMs
                )
            }
        )
    }

    static func data(_ report: SanitizedDiagnosticReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    private static func refreshStateLabel(_ state: RefreshState) -> String {
        switch state {
        case .idle: "idle"
        case .refreshing: "refreshing"
        case .success: "updated"
        case .stale: "stale"
        case .failure: "error"
        }
    }
}
