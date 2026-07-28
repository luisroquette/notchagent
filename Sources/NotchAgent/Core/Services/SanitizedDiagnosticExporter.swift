import Foundation

struct SanitizedDiagnosticReport: Codable, Sendable {
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
}

enum SanitizedDiagnosticExporter {
    @MainActor
    static func report(
        settings: AppSettings,
        snapshots: [ProviderID: UsageSnapshot],
        refreshStates: [ProviderID: RefreshState],
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
            schemaVersion: 1,
            generatedAt: generatedAt,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            configuredAPIAccountCount: accounts.count,
            providers: providerRecords,
            accounts: accountRecords
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
