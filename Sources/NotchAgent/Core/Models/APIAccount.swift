import Foundation

/// A user-configured API account. The label and optional identifier are safe
/// to persist; the credential itself lives only in the macOS Keychain.
public struct APIAccount: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var service: APIServiceID
    public var label: String
    public var identifier: String
    public var enabled: Bool
    /// Stable Keychain account name. Legacy service entries reuse their old
    /// service key so existing credentials remain available after migration.
    public var keychainAccount: String
    /// Service that last saved a credential for this account. Keeping this
    /// non-secret association prevents a key from being sent to a different
    /// vendor if the user changes the account's service in Settings.
    public var credentialService: APIServiceID?
    /// Non-secret revision used to invalidate the in-memory quota cache after
    /// the user replaces a Keychain credential.
    public var credentialRevision: Date?
    /// User-entered recurring subscription price in BRL. This is used only
    /// when a vendor does not provide an authoritative upcoming invoice.
    public var monthlyPlanBRL: Decimal?

    public init(
        id: UUID = UUID(),
        service: APIServiceID,
        label: String? = nil,
        identifier: String = "",
        enabled: Bool = true,
        keychainAccount: String? = nil,
        credentialService: APIServiceID? = nil,
        credentialRevision: Date? = nil,
        monthlyPlanBRL: Decimal? = nil
    ) {
        self.id = id
        self.service = service
        self.label = label ?? service.displayName
        self.identifier = identifier
        self.enabled = enabled
        self.keychainAccount = keychainAccount ?? "account-\(id.uuidString.lowercased())"
        self.credentialService = credentialService
        self.credentialRevision = credentialRevision
        self.monthlyPlanBRL = monthlyPlanBRL
    }
}

/// Describes the monetary figure supplied directly by an API. Values are
/// retained in USD and converted only for display using the user's own rate.
public enum APIAccountMoneyKind: String, Codable, Sendable, Hashable {
    case spend
    case balance
    case remaining
}

/// Provenance attached to each financial/quota field. A value without an
/// origin is never presented as official.
public enum APIAccountDataOrigin: String, Codable, Sendable, Hashable {
    case officialAPI
    case officialPortal
    case manual
    case derivedFromOfficial
}

public struct APIAccountFieldOrigins: Codable, Sendable, Hashable {
    public var spend: APIAccountDataOrigin?
    public var balance: APIAccountDataOrigin?
    public var recharge: APIAccountDataOrigin?
    public var plan: APIAccountDataOrigin?
    public var quota: APIAccountDataOrigin?

    public init(
        spend: APIAccountDataOrigin? = nil,
        balance: APIAccountDataOrigin? = nil,
        recharge: APIAccountDataOrigin? = nil,
        plan: APIAccountDataOrigin? = nil,
        quota: APIAccountDataOrigin? = nil
    ) {
        self.spend = spend
        self.balance = balance
        self.recharge = recharge
        self.plan = plan
        self.quota = quota
    }
}

/// Per-account read state. This remains separate from provider health because
/// one broken login must not erase valid data from the other accounts.
public enum APIAccountReadStatus: String, Codable, Sendable, Hashable {
    case updated
    case partial
    case needsCredential
    case needsLogin
    case unavailable
    case stale
}

/// Comparable spend windows accepted by the unified financial dashboard.
/// A missing value means the vendor did not expose a period that can safely
/// be combined with other providers.
public enum APIAccountSpendPeriod: String, Codable, Sendable, Hashable {
    case rolling28Days
    case rolling30Days
    case currentCalendarMonth

    public var dayCount: Int? {
        switch self {
        case .rolling28Days: 28
        case .rolling30Days: 30
        case .currentCalendarMonth: nil
        }
    }
}

public enum APIAccountSpendWindow {
    public static let duration: TimeInterval = 30 * 24 * 60 * 60

    public static func rolling28Days(endingAt end: Date = Date()) -> DateInterval {
        DateInterval(start: end.addingTimeInterval(-28 * 24 * 60 * 60), end: end)
    }

    public static func rolling30Days(endingAt end: Date = Date()) -> DateInterval {
        DateInterval(start: end.addingTimeInterval(-duration), end: end)
    }

    public static func currentCalendarMonth(
        endingAt end: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval {
        let start = calendar.dateInterval(of: .month, for: end)?.start
            ?? calendar.startOfDay(for: end)
        return DateInterval(start: start, end: end)
    }
}

/// Safe, display-ready result for one configured API account. It carries no
/// credential, request content, or identity data beyond the label the user
/// chose in Settings.
public struct APIAccountUsage: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID { accountID }
    public var accountID: UUID
    public var label: String
    public var service: APIServiceID
    public var capturedAt: Date?
    public var usedPercent: Double?
    public var resetsAt: Date?
    public var summary: String
    public var monetaryUSD: Double?
    public var monetaryKind: APIAccountMoneyKind?
    /// Actual spend reported by the vendor. It is included in unified totals
    /// only when the accompanying period and exact bounds are present.
    public var monthlySpendUSD: Double?
    /// Native BRL spend reported by the vendor. This remains in BRL so a later
    /// exchange-rate refresh cannot rewrite historical official values.
    public var monthlySpendBRL: Decimal?
    public var spendPeriod: APIAccountSpendPeriod?
    public var spendWindowStart: Date?
    public var spendWindowEnd: Date?
    /// Prepaid or remaining money reported by the vendor. This is separate
    /// from spend so the UI can show both values at once.
    public var balanceUSD: Double?
    /// Successful top-ups reported by the vendor for the same explicit window
    /// as spend. Top-ups are never counted as consumption.
    public var rechargeUSD: Double?
    public var rechargeBRL: Decimal?
    /// Subscription amount exposed by the vendor for the next monthly invoice.
    public var monthlyPlanUSD: Double?
    /// Native BRL amount exposed by the vendor. It must never be converted
    /// through USD because doing so would introduce exchange-rate drift.
    public var monthlyPlanBRL: Decimal?
    /// Native balance for prepaid/extra usage credits exposed in BRL.
    public var balanceBRL: Decimal?
    public var planName: String?
    public var seatCount: Int?
    public var cycleUsed: Double?
    public var cycleLimit: Double?
    public var cycleRemaining: Double?
    public var cycleOverage: Double?
    public var cycleUnit: String?
    /// Vendor-owned billing scope used to avoid counting the same project
    /// twice when multiple credentials belong to it. This is non-secret and
    /// is never presented as a user/profile identity.
    public var billingScopeID: String?
    public var readStatus: APIAccountReadStatus?
    public var origins: APIAccountFieldOrigins?
    /// Stable, non-sensitive discrepancy codes produced when two official
    /// sources expose the same field outside the accepted tolerance.
    public var verificationFindings: [String]?

    public init(
        accountID: UUID,
        label: String,
        service: APIServiceID,
        capturedAt: Date? = nil,
        usedPercent: Double?,
        resetsAt: Date?,
        summary: String,
        monetaryUSD: Double? = nil,
        monetaryKind: APIAccountMoneyKind? = nil,
        monthlySpendUSD: Double? = nil,
        monthlySpendBRL: Decimal? = nil,
        spendPeriod: APIAccountSpendPeriod? = nil,
        spendWindowStart: Date? = nil,
        spendWindowEnd: Date? = nil,
        balanceUSD: Double? = nil,
        rechargeUSD: Double? = nil,
        rechargeBRL: Decimal? = nil,
        monthlyPlanUSD: Double? = nil,
        monthlyPlanBRL: Decimal? = nil,
        balanceBRL: Decimal? = nil,
        planName: String? = nil,
        seatCount: Int? = nil,
        cycleUsed: Double? = nil,
        cycleLimit: Double? = nil,
        cycleRemaining: Double? = nil,
        cycleOverage: Double? = nil,
        cycleUnit: String? = nil,
        billingScopeID: String? = nil,
        readStatus: APIAccountReadStatus? = nil,
        origins: APIAccountFieldOrigins? = nil,
        verificationFindings: [String] = []
    ) {
        self.accountID = accountID
        self.label = label
        self.service = service
        self.capturedAt = capturedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.summary = summary
        self.monetaryUSD = monetaryUSD
        self.monetaryKind = monetaryKind
        self.monthlySpendUSD = monthlySpendUSD
        self.monthlySpendBRL = monthlySpendBRL
        self.spendPeriod = spendPeriod
        self.spendWindowStart = spendWindowStart
        self.spendWindowEnd = spendWindowEnd
        self.balanceUSD = balanceUSD
        self.rechargeUSD = rechargeUSD
        self.rechargeBRL = rechargeBRL
        self.monthlyPlanUSD = monthlyPlanUSD
        self.monthlyPlanBRL = monthlyPlanBRL
        self.balanceBRL = balanceBRL
        self.planName = planName
        self.seatCount = seatCount
        self.cycleUsed = cycleUsed
        self.cycleLimit = cycleLimit
        self.cycleRemaining = cycleRemaining
        self.cycleOverage = cycleOverage
        self.cycleUnit = cycleUnit
        self.billingScopeID = billingScopeID
        self.readStatus = readStatus
        self.origins = origins
        self.verificationFindings = verificationFindings.isEmpty ? nil : verificationFindings
    }
}

public extension APIAccountUsage {
    /// Exact spend for the vendor-reported window. This may be shown on an
    /// individual card, but only 30-day values are combined in the total.
    var reportedSpendUSD: Double? {
        guard spendPeriod != nil,
              spendWindowStart != nil,
              spendWindowEnd != nil
        else { return nil }
        return monthlySpendUSD
    }

    var reportedSpendBRL: Decimal? {
        guard spendPeriod != nil,
              spendWindowStart != nil,
              spendWindowEnd != nil
        else { return nil }
        return monthlySpendBRL
    }

    /// The only spend value allowed into cross-provider totals.
    var rolling30DaySpendUSD: Double? {
        guard spendPeriod == .rolling30Days,
              spendWindowStart != nil,
              spendWindowEnd != nil
        else { return nil }
        return monthlySpendUSD
    }
}
