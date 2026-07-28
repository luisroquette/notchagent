import Foundation

struct APIAccountDashboardRow: Identifiable {
    let account: APIAccount
    let usage: APIAccountUsage?

    var id: UUID { account.id }
}

struct APIAccountFinancialSummary: Equatable {
    let consumedUSD: Double?
    let consumedDays: Int?
    let spendPeriod: APIAccountSpendPeriod?
    let remainingUSD: Double?

    var availableUSD: Double? {
        guard let consumedUSD, let remainingUSD else { return nil }
        return consumedUSD + remainingUSD
    }

    var isComplete: Bool {
        availableUSD != nil
    }

    init(usage: APIAccountUsage?) {
        consumedUSD = usage?.reportedSpendUSD
        consumedDays = usage?.spendPeriod?.dayCount
        spendPeriod = usage?.spendPeriod
        remainingUSD = usage?.balanceUSD
            ?? ((usage?.monetaryKind == .balance || usage?.monetaryKind == .remaining)
                ? usage?.monetaryUSD
                : nil)
    }
}

enum APIAccountDisplayConfidence: String, Equatable {
    case officialAPI
    case officialPortal
    case manual
    case derived
    case unavailable

    init(origin: APIAccountDataOrigin?) {
        switch origin {
        case .officialAPI: self = .officialAPI
        case .officialPortal: self = .officialPortal
        case .manual: self = .manual
        case .derivedFromOfficial: self = .derived
        case nil: self = .unavailable
        }
    }

    var label: String {
        switch self {
        case .officialAPI: "API OFICIAL"
        case .officialPortal: "PORTAL OFICIAL"
        case .manual: "VALOR MANUAL"
        case .derived: "ESTIMADO PELO PLANO"
        case .unavailable: "NÃO INFORMADO"
        }
    }
}

struct APIAccountMoneyPresentation: Equatable {
    var amountBRL: Decimal?
    var confidence: APIAccountDisplayConfidence
}

struct APIAccountFinancePresentation: Equatable {
    var spend: APIAccountMoneyPresentation
    var balance: APIAccountMoneyPresentation
    var plan: APIAccountMoneyPresentation
    var spendLabel: String

    init(account: APIAccount, usage: APIAccountUsage?, brlPerUSD: Decimal?) {
        let origins = usage?.origins ?? APIAccountFieldOrigins()
        let planValue: Decimal? = {
            if let brl = usage?.monthlyPlanBRL { return brl }
            if let brl = account.monthlyPlanBRL { return brl }
            guard let usd = usage?.monthlyPlanUSD, let brlPerUSD else { return nil }
            return Decimal(usd) * brlPerUSD
        }()
        let planConfidence: APIAccountDisplayConfidence = {
            if usage?.monthlyPlanBRL != nil || usage?.monthlyPlanUSD != nil {
                return APIAccountDisplayConfidence(origin: origins.plan)
            }
            return account.monthlyPlanBRL == nil ? .unavailable : .manual
        }()

        let officialSpend: Decimal? = {
            if let brl = usage?.reportedSpendBRL { return brl }
            guard let usd = usage?.reportedSpendUSD, let brlPerUSD else { return nil }
            return Decimal(usd) * brlPerUSD
        }()
        let officialBalance: Decimal? = {
            if let brl = usage?.balanceBRL { return brl }
            guard let usd = usage?.balanceUSD, let brlPerUSD else { return nil }
            return Decimal(usd) * brlPerUSD
        }()
        let derivedQuota: (spend: Decimal, balance: Decimal)? = {
            guard let planValue,
                  let used = usage?.cycleUsed,
                  let limit = usage?.cycleLimit,
                  limit > 0
            else { return nil }
            let remaining = usage?.cycleRemaining ?? max(limit - used, 0)
            return (
                planValue * Decimal(used / limit),
                planValue * Decimal(max(remaining, 0) / limit)
            )
        }()

        if let officialSpend {
            spend = APIAccountMoneyPresentation(
                amountBRL: officialSpend,
                confidence: APIAccountDisplayConfidence(origin: origins.spend)
            )
        } else if let derivedQuota {
            spend = APIAccountMoneyPresentation(amountBRL: derivedQuota.spend, confidence: .derived)
        } else {
            spend = APIAccountMoneyPresentation(amountBRL: nil, confidence: .unavailable)
        }

        if let officialBalance {
            balance = APIAccountMoneyPresentation(
                amountBRL: officialBalance,
                confidence: APIAccountDisplayConfidence(origin: origins.balance)
            )
        } else if let derivedQuota {
            balance = APIAccountMoneyPresentation(amountBRL: derivedQuota.balance, confidence: .derived)
        } else {
            balance = APIAccountMoneyPresentation(amountBRL: nil, confidence: .unavailable)
        }

        plan = APIAccountMoneyPresentation(amountBRL: planValue, confidence: planConfidence)
        switch usage?.spendPeriod {
        case .rolling28Days:
            spendLabel = "GASTO 28 DIAS"
        case .currentCalendarMonth:
            spendLabel = "GASTO MÊS ATUAL"
        case .rolling30Days, nil:
            spendLabel = "GASTO 30 DIAS"
        }
    }
}

enum APIAccountOrdering {
    static func moving(_ accounts: [APIAccount], sourceID: UUID, targetID: UUID) -> [APIAccount] {
        guard sourceID != targetID,
              let sourceIndex = accounts.firstIndex(where: { $0.id == sourceID }),
              let originalTargetIndex = accounts.firstIndex(where: { $0.id == targetID })
        else { return accounts }

        var reordered = accounts
        let movingAccount = reordered.remove(at: sourceIndex)
        guard let targetIndex = reordered.firstIndex(where: { $0.id == targetID }) else { return accounts }
        let destination = sourceIndex < originalTargetIndex ? targetIndex + 1 : targetIndex
        reordered.insert(movingAccount, at: min(destination, reordered.endIndex))
        return reordered
    }
}
