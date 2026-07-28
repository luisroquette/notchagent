import Foundation

struct APIAccountAuditTolerance: Codable, Equatable, Sendable {
    var monetaryUSD: Double = 0.02
    var monetaryBRL: Decimal = Decimal(string: "0.10")!
    var quotaUnits: Double = 1
    var windowSeconds: TimeInterval = 15 * 60
}

enum APIAccountAuditOutcome: String, Codable, Sendable {
    case verified
    case partial
    case blocked
    case invalid
}

struct APIAccountAuditItem: Codable, Sendable {
    var accountID: UUID
    var service: APIServiceID
    var outcome: APIAccountAuditOutcome
    var readStatus: APIAccountReadStatus
    var sources: [APIAccountDataOrigin]
    var spendPeriod: APIAccountSpendPeriod?
    var spendWindowStart: Date?
    var spendWindowEnd: Date?
    var tolerance: APIAccountAuditTolerance
    var findings: [String]
}

enum APIAccountIntegrityAuditor {
    static func audit(
        accounts: [APIAccount],
        usages: [APIAccountUsage],
        tolerance: APIAccountAuditTolerance = APIAccountAuditTolerance()
    ) -> [APIAccountAuditItem] {
        let usageByID = Dictionary(uniqueKeysWithValues: usages.map { ($0.accountID, $0) })
        return accounts.filter(\.enabled).map { account in
            guard let usage = usageByID[account.id] else {
                return APIAccountAuditItem(
                    accountID: account.id,
                    service: account.service,
                    outcome: .invalid,
                    readStatus: .unavailable,
                    sources: [],
                    tolerance: tolerance,
                    findings: ["missing_account_result"]
                )
            }
            return audit(account: account, usage: usage, tolerance: tolerance)
        }
    }

    static func audit(
        account: APIAccount,
        usage: APIAccountUsage,
        tolerance: APIAccountAuditTolerance = APIAccountAuditTolerance()
    ) -> APIAccountAuditItem {
        var findings: [String] = usage.verificationFindings ?? []
        let origins = usage.origins ?? APIAccountFieldOrigins()

        validateMoney(usage.monthlySpendUSD, name: "spend_usd", findings: &findings)
        validateMoney(usage.monthlySpendBRL, name: "spend_brl", findings: &findings)
        validateMoney(usage.balanceUSD, name: "balance_usd", findings: &findings)
        validateMoney(usage.rechargeUSD, name: "recharge_usd", findings: &findings)
        validateMoney(usage.monthlyPlanUSD, name: "plan_usd", findings: &findings)
        validateMoney(usage.balanceBRL, name: "balance_brl", findings: &findings)
        validateMoney(usage.rechargeBRL, name: "recharge_brl", findings: &findings)
        validateMoney(usage.monthlyPlanBRL, name: "plan_brl", findings: &findings)

        if usage.monthlySpendUSD != nil || usage.monthlySpendBRL != nil {
            if origins.spend == nil { findings.append("spend_without_source") }
            if usage.spendPeriod == nil
                || usage.spendWindowStart == nil
                || usage.spendWindowEnd == nil {
                findings.append("spend_without_exact_window")
            }
        }
        if usage.balanceUSD != nil || usage.balanceBRL != nil, origins.balance == nil {
            findings.append("balance_without_source")
        }
        if usage.rechargeUSD != nil || usage.rechargeBRL != nil, origins.recharge == nil {
            findings.append("recharge_without_source")
        }
        if usage.monthlyPlanUSD != nil || usage.monthlyPlanBRL != nil, origins.plan == nil {
            findings.append("plan_without_source")
        }
        if usage.cycleUsed != nil || usage.cycleLimit != nil, origins.quota == nil {
            findings.append("quota_without_source")
        }

        validateWindow(usage, tolerance: tolerance, findings: &findings)
        validateQuota(usage, tolerance: tolerance, findings: &findings)

        let status = usage.readStatus ?? .unavailable
        let outcome: APIAccountAuditOutcome
        if !findings.isEmpty {
            outcome = .invalid
        } else {
            switch status {
            case .updated:
                outcome = .verified
            case .partial, .stale:
                outcome = .partial
            case .needsCredential, .needsLogin, .unavailable:
                outcome = .blocked
            }
        }

        let sources = [
            origins.spend,
            origins.balance,
            origins.recharge,
            origins.plan,
            origins.quota,
        ].compactMap { $0 }.reduce(into: [APIAccountDataOrigin]()) { result, origin in
            if !result.contains(origin) { result.append(origin) }
        }

        return APIAccountAuditItem(
            accountID: account.id,
            service: account.service,
            outcome: outcome,
            readStatus: status,
            sources: sources,
            spendPeriod: usage.spendPeriod,
            spendWindowStart: usage.spendWindowStart,
            spendWindowEnd: usage.spendWindowEnd,
            tolerance: tolerance,
            findings: findings
        )
    }

    private static func validateWindow(
        _ usage: APIAccountUsage,
        tolerance: APIAccountAuditTolerance,
        findings: inout [String]
    ) {
        guard let period = usage.spendPeriod,
              let start = usage.spendWindowStart,
              let end = usage.spendWindowEnd
        else { return }
        guard end >= start else {
            findings.append("invalid_spend_window")
            return
        }
        guard let days = period.dayCount else { return }
        let expected = TimeInterval(days * 24 * 60 * 60)
        if abs(end.timeIntervalSince(start) - expected) > tolerance.windowSeconds {
            findings.append("spend_window_mismatch")
        }
    }

    private static func validateQuota(
        _ usage: APIAccountUsage,
        tolerance: APIAccountAuditTolerance,
        findings: inout [String]
    ) {
        for (name, value) in [
            ("cycle_used", usage.cycleUsed),
            ("cycle_limit", usage.cycleLimit),
            ("cycle_remaining", usage.cycleRemaining),
            ("cycle_overage", usage.cycleOverage),
        ] where value.map({ $0 < 0 }) == true {
            findings.append("\(name)_negative")
        }

        guard let used = usage.cycleUsed, let limit = usage.cycleLimit else { return }
        let expectedRemaining = max(0, limit - used)
        let expectedOverage = max(0, used - limit)
        if let remaining = usage.cycleRemaining,
           abs(remaining - expectedRemaining) > tolerance.quotaUnits {
            findings.append("cycle_remaining_mismatch")
        }
        if let overage = usage.cycleOverage,
           abs(overage - expectedOverage) > tolerance.quotaUnits {
            findings.append("cycle_overage_mismatch")
        }
    }

    private static func validateMoney(
        _ value: Double?,
        name: String,
        findings: inout [String]
    ) {
        if let value, !value.isFinite || value < 0 {
            findings.append("\(name)_invalid")
        }
    }

    private static func validateMoney(
        _ value: Decimal?,
        name: String,
        findings: inout [String]
    ) {
        if let value, value < 0 {
            findings.append("\(name)_invalid")
        }
    }
}
