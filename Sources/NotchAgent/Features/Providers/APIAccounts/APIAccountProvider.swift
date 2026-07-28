import Foundation
import Security

struct AccountQuota: Sendable, Equatable {
    var service: APIServiceID
    var usedPercent: Double?
    var resetsAt: Date?
    var note: String
    var monetaryUSD: Double? = nil
    var monetaryKind: APIAccountMoneyKind? = nil
    var monthlySpendUSD: Double? = nil
    var monthlySpendBRL: Decimal? = nil
    var spendPeriod: APIAccountSpendPeriod? = nil
    var spendWindowStart: Date? = nil
    var spendWindowEnd: Date? = nil
    var balanceUSD: Double? = nil
    var rechargeUSD: Double? = nil
    var rechargeBRL: Decimal? = nil
    var monthlyPlanUSD: Double? = nil
    var monthlyPlanBRL: Decimal? = nil
    var balanceBRL: Decimal? = nil
    var planName: String? = nil
    var seatCount: Int? = nil
    var cycleUsed: Double? = nil
    var cycleLimit: Double? = nil
    var cycleRemaining: Double? = nil
    var cycleOverage: Double? = nil
    var cycleUnit: String? = nil
    var billingScopeID: String? = nil
    var origins = APIAccountFieldOrigins()
    var verificationFindings: [String] = []
}

private extension AccountQuota {
    mutating func tagMissingOrigins(_ origin: APIAccountDataOrigin) {
        if monthlySpendUSD != nil || monthlySpendBRL != nil, origins.spend == nil { origins.spend = origin }
        if balanceUSD != nil || balanceBRL != nil, origins.balance == nil { origins.balance = origin }
        if rechargeUSD != nil || rechargeBRL != nil, origins.recharge == nil { origins.recharge = origin }
        if monthlyPlanUSD != nil || monthlyPlanBRL != nil, origins.plan == nil { origins.plan = origin }
        if usedPercent != nil
            || cycleUsed != nil
            || cycleLimit != nil
            || cycleRemaining != nil
            || cycleOverage != nil,
           origins.quota == nil {
            origins.quota = origin
        }
    }

    func tagged(_ origin: APIAccountDataOrigin) -> AccountQuota {
        var copy = self
        copy.tagMissingOrigins(origin)
        return copy
    }

    mutating func mergeOrigins(api: AccountQuota?, portal: AccountQuota?) {
        origins.spend = portal?.origins.spend ?? api?.origins.spend ?? origins.spend
        origins.balance = api?.origins.balance ?? portal?.origins.balance ?? origins.balance
        origins.recharge = portal?.origins.recharge ?? api?.origins.recharge ?? origins.recharge
        origins.plan = portal?.origins.plan ?? api?.origins.plan ?? origins.plan
        origins.quota = api?.origins.quota ?? portal?.origins.quota ?? origins.quota
    }

    mutating func reconcile(api: AccountQuota?, portal: AccountQuota?) {
        verificationFindings = Array(Set(
            (api?.verificationFindings ?? [])
                + (portal?.verificationFindings ?? [])
                + APIAccountOfficialComparator.findings(api: api, portal: portal)
        )).sorted()
    }
}

enum APIAccountOfficialComparator {
    static func findings(
        api: AccountQuota?,
        portal: AccountQuota?,
        tolerance: APIAccountAuditTolerance = APIAccountAuditTolerance()
    ) -> [String] {
        guard let api, let portal else { return [] }
        var findings: [String] = []
        compare(api.balanceUSD, portal.balanceUSD, tolerance.monetaryUSD, "balance_usd_source_mismatch", &findings)
        compare(api.rechargeUSD, portal.rechargeUSD, tolerance.monetaryUSD, "recharge_usd_source_mismatch", &findings)
        compare(api.monthlyPlanUSD, portal.monthlyPlanUSD, tolerance.monetaryUSD, "plan_usd_source_mismatch", &findings)
        compare(api.balanceBRL, portal.balanceBRL, tolerance.monetaryBRL, "balance_brl_source_mismatch", &findings)
        compare(api.rechargeBRL, portal.rechargeBRL, tolerance.monetaryBRL, "recharge_brl_source_mismatch", &findings)
        compare(api.monthlyPlanBRL, portal.monthlyPlanBRL, tolerance.monetaryBRL, "plan_brl_source_mismatch", &findings)

        if api.spendPeriod == portal.spendPeriod,
           api.spendPeriod != nil {
            compare(
                api.monthlySpendUSD,
                portal.monthlySpendUSD,
                tolerance.monetaryUSD,
                "spend_usd_source_mismatch",
                &findings
            )
            compare(
                api.monthlySpendBRL,
                portal.monthlySpendBRL,
                tolerance.monetaryBRL,
                "spend_brl_source_mismatch",
                &findings
            )
        }
        if api.cycleUnit == portal.cycleUnit,
           api.cycleUnit != nil {
            compare(api.cycleUsed, portal.cycleUsed, tolerance.quotaUnits, "quota_used_source_mismatch", &findings)
            compare(api.cycleLimit, portal.cycleLimit, tolerance.quotaUnits, "quota_limit_source_mismatch", &findings)
            compare(api.cycleRemaining, portal.cycleRemaining, tolerance.quotaUnits, "quota_remaining_source_mismatch", &findings)
        }
        return findings
    }

    private static func compare(
        _ left: Double?,
        _ right: Double?,
        _ tolerance: Double,
        _ finding: String,
        _ findings: inout [String]
    ) {
        if let left, let right, abs(left - right) > tolerance {
            findings.append(finding)
        }
    }

    private static func compare(
        _ left: Decimal?,
        _ right: Decimal?,
        _ tolerance: Decimal,
        _ finding: String,
        _ findings: inout [String]
    ) {
        guard let left, let right else { return }
        let delta = abs(
            NSDecimalNumber(decimal: left - right).doubleValue
        )
        if delta > NSDecimalNumber(decimal: tolerance).doubleValue {
            findings.append(finding)
        }
    }
}

actor APIAccountSnapshotCache {
    private var value: UsageSnapshot?
    private var fingerprint: String?
    private var capturedAt = Date.distantPast
    private let minimumInterval: TimeInterval = 15 * 60
    private var revision: UInt64 = 0

    func fresh(fingerprint: String, now: Date = Date()) -> UsageSnapshot? {
        guard self.fingerprint == fingerprint,
              now.timeIntervalSince(capturedAt) < minimumInterval else { return nil }
        return value
    }

    func currentRevision() -> UInt64 {
        revision
    }

    func store(_ snapshot: UsageSnapshot, fingerprint: String, ifRevision expected: UInt64) {
        guard revision == expected else { return }
        value = snapshot
        self.fingerprint = fingerprint
        capturedAt = Date()
    }

    func clear() {
        revision &+= 1
        value = nil
        fingerprint = nil
        capturedAt = .distantPast
    }
}

enum GoogleCloudCredentialProvider {
    private static let executableCandidates = [
        "/opt/homebrew/bin/gcloud",
        "/usr/local/bin/gcloud",
        "/usr/bin/gcloud",
    ]

    static func accessToken(fallback: String?) async -> String? {
        if let token = await applicationDefaultAccessToken() {
            return token
        }
        return normalizedToken(fallback)
    }

    static func normalizedToken(_ value: String?) -> String? {
        guard let token = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }
        return token
    }

    private static func applicationDefaultAccessToken() async -> String? {
        await Task.detached(priority: .utility) {
            guard let executable = executableCandidates.first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            }) else { return nil }

            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["auth", "application-default", "print-access-token"]
            process.standardOutput = output
            process.standardError = errors

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                return normalizedToken(String(data: data, encoding: .utf8))
            } catch {
                return nil
            }
        }.value
    }
}

/// Stores account-monitor credentials independently of Preferences and history.
/// Values are never logged or included in a snapshot.
enum APIAccountCredentialStore {
    private static let service = "br.com.lfrprojects.notchagent.api-account-monitor"

    static func key(for keychainAccount: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    @discardableResult
    static func save(_ value: String, for keychainAccount: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
        ]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var create = query
        create[kSecValueData as String] = data
        create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(create as CFDictionary, nil) == errSecSuccess
    }

    static func key(for account: APIAccount) -> String? {
        // Older accounts have no association and remain compatible. Once a
        // credential has been saved by the current UI, it is valid only for
        // the service selected at that time.
        guard credentialIsCompatible(with: account) else { return nil }
        return key(for: account.keychainAccount)
    }

    static func credentialIsCompatible(with account: APIAccount) -> Bool {
        account.credentialService == nil || account.credentialService == account.service
    }

    @discardableResult
    static func save(_ value: String, for account: APIAccount) -> Bool {
        save(value, for: account.keychainAccount)
    }
}

enum APIAccountProbe {
    static func getJSON(url: URL, headers: [String: String], session: URLSession = .shared) async -> Data? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    static func postJSON(url: URL, headers: [String: String], body: [String: Any], session: URLSession = .shared) async -> Data? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        guard let encodedBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = encodedBody
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Anthropic reports costs in the currency's lowest unit. For USD that
    /// means cents, so `123.45` represents USD 1.2345.
    static func anthropicCost(data: Data, window: DateInterval? = nil) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = root["data"] as? [[String: Any]]
        else { return nil }
        let cents = buckets.reduce(0.0) { bucketTotal, bucket in
            bucketTotal + (bucket["results"] as? [[String: Any]] ?? []).reduce(0.0) { resultTotal, result in
                guard (result["currency"] as? String)?.uppercased() == "USD" else { return resultTotal }
                return resultTotal + (numericValue(result["amount"]) ?? 0)
            }
        }
        let usd = cents / 100
        return AccountQuota(
            service: .anthropicAPI,
            usedPercent: nil,
            resetsAt: nil,
            note: String(
                format: "Anthropic API spend last 30 days: %.2f USD",
                locale: Locale(identifier: "en_US_POSIX"),
                usd
            ),
            monetaryUSD: usd,
            monetaryKind: .spend,
            monthlySpendUSD: usd,
            spendPeriod: window == nil ? nil : .rolling30Days,
            spendWindowStart: window?.start,
            spendWindowEnd: window?.end
        )
    }

    static func fetchAnthropicCost(
        adminKey: String,
        now: Date = Date(),
        session: URLSession = .shared
    ) async -> AccountQuota? {
        let window = APIAccountSpendWindow.rolling30Days(endingAt: now)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard var components = URLComponents(
            string: "https://api.anthropic.com/v1/organizations/cost_report"
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: window.start)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: window.end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]
        guard let url = components.url,
              let data = await getJSON(
                url: url,
                headers: [
                    "x-api-key": adminKey,
                    "anthropic-version": "2023-06-01",
                    "User-Agent": "NotchAgent/1.0",
                ],
                session: session
              )
        else { return nil }
        return anthropicCost(data: data, window: window)
    }

    /// Pure parser for `GET /v1/user/subscription`. It intentionally reads
    /// only quota fields and ignores identity, billing and invoice data.
    static func elevenLabsQuota(data: Data, now: Date = Date()) -> AccountQuota? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let used = object["character_count"] as? Double,
              let limit = object["character_limit"] as? Double,
              limit > 0 else { return nil }
        let reset = (object["next_character_count_reset_unix"] as? Double).map(Date.init(timeIntervalSince1970:))
        let currency = (object["currency"] as? String)?.uppercased() ?? "USD"
        let invoice = object["next_invoice"] as? [String: Any]
        let planUSD = currency == "USD"
            ? numericValue(invoice?["amount_due_cents"]).map { $0 / 100 }
            : nil
        let overage = object["current_overage"] as? [String: Any]
        let overageUSD = (overage?["currency"] as? String)?.uppercased() == "USD"
            ? numericValue(overage?["amount"]).flatMap { $0 > 0 ? $0 : nil }
            : nil
        let percent = min(max(used / limit * 100, 0), 100)
        return AccountQuota(
            service: .elevenLabs,
            usedPercent: percent,
            resetsAt: reset,
            note: "ElevenLabs: \(Int(used)) / \(Int(limit)) credits used",
            monthlySpendUSD: overageUSD,
            monthlyPlanUSD: planUSD,
            cycleUsed: used,
            cycleLimit: limit,
            cycleUnit: "créditos"
        )
    }

    static func fetchElevenLabs(key: String, session: URLSession = .shared) async -> AccountQuota? {
        guard let data = await getJSON(
            url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!,
            headers: ["xi-api-key": key],
            session: session
        ) else { return nil }
        return elevenLabsQuota(data: data)
    }

    /// Firecrawl v2 returns remaining and plan credits for the authenticated team.
    static func firecrawlQuota(data: Data) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["data"] as? [String: Any],
              let remaining = body["remainingCredits"] as? Double,
              let plan = body["planCredits"] as? Double,
              plan > 0 else { return nil }
        let reset = (body["billingPeriodEnd"] as? String).flatMap(Timestamps.parseISO8601)
        let available = max(remaining, 0)
        let overage = max(-remaining, 0)
        let used = max(plan - remaining, 0)
        let detail = overage > 0
            ? "0 credits remaining of \(Int(plan)) · \(Int(overage)) overage"
            : "\(Int(available)) credits remaining of \(Int(plan))"
        return AccountQuota(
            service: .firecrawl,
            usedPercent: min(max(used / plan * 100, 0), 100),
            resetsAt: reset,
            note: "Firecrawl: \(detail)",
            cycleUsed: used,
            cycleLimit: plan,
            cycleRemaining: available,
            cycleOverage: overage,
            cycleUnit: "créditos",
            origins: APIAccountFieldOrigins(quota: .officialAPI)
        )
    }

    static func fetchFirecrawl(key: String, session: URLSession = .shared) async -> AccountQuota? {
        guard let data = await getJSON(
            url: URL(string: "https://api.firecrawl.dev/v2/team/credit-usage")!,
            headers: ["Authorization": "Bearer \(key)"],
            session: session
        ) else { return nil }
        return firecrawlQuota(data: data)
    }

    /// DeepSeek exposes a monetary balance but not the original credit cap;
    /// report it faithfully as a balance, never as a made-up percentage.
    static func deepSeekBalance(data: Data) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let balances = root["balance_infos"] as? [[String: Any]],
              !balances.isEmpty else { return nil }
        let amounts = balances.compactMap { entry -> String? in
            guard let amount = entry["total_balance"] as? String,
                  let currency = entry["currency"] as? String else { return nil }
            return "\(amount) \(currency)"
        }
        guard !amounts.isEmpty else { return nil }
        let usdBalances = balances.compactMap { entry -> Double? in
            guard (entry["currency"] as? String)?.uppercased() == "USD",
                  let amount = entry["total_balance"] as? String else { return nil }
            return Double(amount)
        }
        let usdBalance = usdBalances.reduce(0, +)
        return AccountQuota(
            service: .deepSeek,
            usedPercent: nil,
            resetsAt: nil,
            note: "DeepSeek balance: \(amounts.joined(separator: ", "))",
            monetaryUSD: usdBalances.isEmpty ? nil : usdBalance,
            monetaryKind: usdBalances.isEmpty ? nil : .balance,
            balanceUSD: usdBalances.isEmpty ? nil : usdBalance
        )
    }

    static func fetchDeepSeek(key: String, session: URLSession = .shared) async -> AccountQuota? {
        guard let data = await getJSON(
            url: URL(string: "https://api.deepseek.com/user/balance")!,
            headers: ["Authorization": "Bearer \(key)"],
            session: session
        ) else { return nil }
        return deepSeekBalance(data: data)
    }

    static func mergeDeepSeek(api: AccountQuota?, console: AccountQuota?) -> AccountQuota? {
        guard api != nil || console != nil else { return nil }
        var merged = console ?? api!
        merged.service = .deepSeek
        merged.balanceUSD = api?.balanceUSD ?? console?.balanceUSD
        merged.monthlySpendUSD = console?.monthlySpendUSD
        merged.monthlySpendBRL = console?.monthlySpendBRL
        merged.spendPeriod = console?.spendPeriod
        merged.spendWindowStart = console?.spendWindowStart
        merged.spendWindowEnd = console?.spendWindowEnd
        merged.monetaryUSD = merged.balanceUSD ?? merged.monthlySpendUSD
        merged.monetaryKind = merged.balanceUSD == nil ? .spend : .balance
        merged.mergeOrigins(api: api, portal: console)
        merged.reconcile(api: api, portal: console)
        let details = [console?.note, api?.note].compactMap { $0 }
        merged.note = details.joined(separator: " · ")
        return merged
    }

    /// OpenAI's Costs API reports actual organization spend, not a prepaid
    /// credit balance. We intentionally label it as spend, not quota.
    static func openAICost(data: Data, window: DateInterval? = nil) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = root["data"] as? [[String: Any]] else { return nil }
        var amount = 0.0
        var currency = "USD"
        var usdAmount = 0.0
        for bucket in buckets {
            for result in bucket["results"] as? [[String: Any]] ?? [] {
                guard let value = (result["amount"] as? [String: Any]) else { continue }
                amount += numericValue(value["value"]) ?? 0
                currency = (value["currency"] as? String)?.uppercased() ?? currency
                if (value["currency"] as? String)?.uppercased() == "USD" {
                    usdAmount += numericValue(value["value"]) ?? 0
                }
            }
        }
        return AccountQuota(
            service: .openAI,
            usedPercent: nil,
            resetsAt: nil,
            note: String(format: "OpenAI spend last 30 days: %.2f %@", locale: Locale(identifier: "en_US_POSIX"), amount, currency),
            monetaryUSD: currency == "USD" ? amount : (usdAmount > 0 ? usdAmount : nil),
            monetaryKind: currency == "USD" || usdAmount > 0 ? .spend : nil,
            monthlySpendUSD: currency == "USD" ? amount : (usdAmount > 0 ? usdAmount : nil),
            spendPeriod: window == nil ? nil : .rolling30Days,
            spendWindowStart: window?.start,
            spendWindowEnd: window?.end
        )
    }

    static func fetchOpenAI(key: String, now: Date = Date(), session: URLSession = .shared) async -> AccountQuota? {
        let window = APIAccountSpendWindow.rolling30Days(endingAt: now)
        let start = Int(window.start.timeIntervalSince1970)
        let end = Int(window.end.timeIntervalSince1970)
        guard var components = URLComponents(string: "https://api.openai.com/v1/organization/costs") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(start)),
            URLQueryItem(name: "end_time", value: String(end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]
        guard let url = components.url,
              let data = await getJSON(url: url, headers: ["Authorization": "Bearer \(key)"], session: session)
        else { return nil }
        return openAICost(data: data, window: window)
    }

    static func mergeOpenAI(api: AccountQuota?, portal: AccountQuota?) -> AccountQuota? {
        guard api != nil || portal != nil else { return nil }
        var merged = api ?? portal!
        merged.service = .openAI
        merged.monthlySpendUSD = api?.monthlySpendUSD
        merged.monthlySpendBRL = api?.monthlySpendBRL
        merged.spendPeriod = api?.spendPeriod
        merged.spendWindowStart = api?.spendWindowStart
        merged.spendWindowEnd = api?.spendWindowEnd
        merged.balanceUSD = portal?.balanceUSD
        merged.monetaryUSD = merged.balanceUSD ?? merged.monthlySpendUSD
        merged.monetaryKind = merged.balanceUSD != nil ? .balance : (merged.monthlySpendUSD != nil ? .spend : nil)
        merged.mergeOrigins(api: api, portal: portal)
        merged.reconcile(api: api, portal: portal)
        var details = [api?.note, portal?.note].compactMap { $0 }
        if merged.balanceUSD == nil {
            details.append("OpenAI prepaid balance is not exposed by the official API; connect the billing portal to read it")
        }
        merged.note = details.joined(separator: " · ")
        return merged
    }

    /// HeyGen v3 exposes one of three billing shapes (wallet, subscription,
    /// usage-based). A percentage is emitted only when the API supplies a cap.
    static func heyGenQuota(data: Data) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["data"] as? [String: Any],
              let billingType = body["billing_type"] as? String else { return nil }

        switch billingType {
        case "wallet":
            guard let wallet = body["wallet"] as? [String: Any],
                  let balance = wallet["remaining_balance"] as? Double else { return nil }
            let currency = (wallet["currency"] as? String ?? "credits").uppercased()
            return AccountQuota(
                service: .heyGen,
                usedPercent: nil,
                resetsAt: nil,
                note: "HeyGen balance: \(balance) \(currency)",
                monetaryUSD: currency == "USD" ? balance : nil,
                monetaryKind: currency == "USD" ? .balance : nil,
                balanceUSD: currency == "USD" ? balance : nil
            )
        case "subscription":
            guard let subscription = body["subscription"] as? [String: Any],
                  let credits = subscription["credits"] as? [String: Any],
                  let premium = credits["premium_credits"] as? [String: Any],
                  let remaining = premium["remaining"] as? Double else { return nil }
            let reset = (premium["resets_at"] as? String).flatMap(Timestamps.parseISO8601)
            return AccountQuota(service: .heyGen, usedPercent: nil, resetsAt: reset, note: "HeyGen premium credits remaining: \(Int(remaining))")
        case "usage_based":
            guard let usage = body["usage_based"] as? [String: Any],
                  let current = usage["spending_current_usd"] as? Double else { return nil }
            let cap = usage["spending_cap_usd"] as? Double
            let percent = cap.flatMap { $0 > 0 ? min(max(current / $0 * 100, 0), 100) : nil }
            let suffix = cap.map { String(format: " / %.2f USD", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            return AccountQuota(
                service: .heyGen,
                usedPercent: percent,
                resetsAt: nil,
                note: String(format: "HeyGen spend: %.2f USD%@", locale: Locale(identifier: "en_US_POSIX"), current, suffix),
                monetaryUSD: current,
                monetaryKind: .spend,
                monthlySpendUSD: current
            )
        default:
            return nil
        }
    }

    static func fetchHeyGen(key: String, session: URLSession = .shared) async -> AccountQuota? {
        guard let data = await getJSON(
            url: URL(string: "https://api.heygen.com/v3/users/me")!,
            headers: ["X-Api-Key": key],
            session: session
        ) else { return nil }
        return heyGenQuota(data: data)
    }

    static func twilioSpend(data: Data, window: DateInterval? = nil) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["usage_records"] as? [[String: Any]]
        else { return nil }
        let totals = records.filter { ($0["category"] as? String) == "totalprice" }
        guard !totals.isEmpty else { return nil }
        let amounts = totals.compactMap { total -> Double? in
            let raw = total["price"]
            return (raw as? Double) ?? (raw as? String).flatMap(Double.init)
        }
        guard amounts.count == totals.count else { return nil }
        let amount = amounts.reduce(0, +)
        let currencies = Set(totals.map { (($0["price_unit"] as? String) ?? "USD").uppercased() })
        guard currencies.count == 1, let currency = currencies.first else { return nil }
        return AccountQuota(
            service: .twilio,
            usedPercent: nil,
            resetsAt: nil,
            note: String(format: "Twilio spend last 30 days: %.2f %@", locale: Locale(identifier: "en_US_POSIX"), amount, currency),
            monetaryUSD: currency == "USD" ? amount : nil,
            monetaryKind: currency == "USD" ? .spend : nil,
            monthlySpendUSD: currency == "USD" ? amount : nil,
            spendPeriod: window == nil ? nil : .rolling30Days,
            spendWindowStart: window?.start,
            spendWindowEnd: window?.end
        )
    }

    static func fetchTwilio(accountSID: String, apiKey: String, now: Date = Date(), session: URLSession = .shared) async -> AccountQuota? {
        let parts = apiKey.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let window = APIAccountSpendWindow.rolling30Days(endingAt: now)
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              let encoded = "\(parts[0]):\(parts[1])".data(using: .utf8)?.base64EncodedString(),
              let escapedSID = accountSID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(string: "https://api.twilio.com/2010-04-01/Accounts/\(escapedSID)/Usage/Records.json")
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "Category", value: "totalprice"),
            URLQueryItem(name: "StartDate", value: dateFormatter.string(from: window.start)),
            URLQueryItem(name: "EndDate", value: dateFormatter.string(from: window.end)),
        ]
        guard let url = components.url else { return nil }
        guard let data = await getJSON(url: url, headers: ["Authorization": "Basic \(encoded)"], session: session) else { return nil }
        return twilioSpend(data: data, window: window)
    }

    /// OpenRouter's key endpoint describes the selected key, not the prepaid
    /// account wallet. A zero key limit is treated as "no configured limit",
    /// never as a zero-dollar account balance.
    static func openRouterQuota(data: Data) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["data"] as? [String: Any],
              let usage = numericValue(body["usage"])
        else { return nil }
        let monthlyUsage = numericValue(body["usage_monthly"]) ?? usage
        let configuredLimit = numericValue(body["limit"]).flatMap { $0 > 0 ? $0 : nil }
        let remaining = configuredLimit.flatMap { _ in numericValue(body["limit_remaining"]) }
        let limit = configuredLimit
        let percent = limit.flatMap { $0 > 0 ? min(max(usage / $0 * 100, 0), 100) : nil }
        let reset = body["limit_reset"] as? String
        var summary = String(
            format: "OpenRouter key spend this month: %.2f USD",
            locale: Locale(identifier: "en_US_POSIX"),
            monthlyUsage
        )
        if let remaining {
            summary += String(
                format: " · key limit remaining: %.2f USD",
                locale: Locale(identifier: "en_US_POSIX"),
                remaining
            )
        }
        if let reset {
            summary += ", resets \(reset)"
        }
        return AccountQuota(
            service: .openRouter,
            usedPercent: percent,
            resetsAt: nil,
            note: summary,
            cycleUsed: usage,
            cycleLimit: limit,
            cycleUnit: "USD"
        )
    }

    /// Account-wide prepaid wallet returned by the credits endpoint.
    static func openRouterCreditsQuota(data: Data) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["data"] as? [String: Any],
              let purchased = numericValue(body["total_credits"]),
              let used = numericValue(body["total_usage"])
        else { return nil }
        let balance = max(purchased - used, 0)
        return AccountQuota(
            service: .openRouter,
            usedPercent: nil,
            resetsAt: nil,
            note: String(
                format: "OpenRouter account balance: %.2f USD",
                locale: Locale(identifier: "en_US_POSIX"),
                balance
            ),
            monetaryUSD: balance,
            monetaryKind: .balance,
            balanceUSD: balance
        )
    }

    static func mergeOpenRouter(key: AccountQuota?, credits: AccountQuota?) -> AccountQuota? {
        guard key != nil || credits != nil else { return nil }
        var merged = key ?? credits!
        if let credits {
            merged.balanceUSD = credits.balanceUSD
            merged.monetaryUSD = credits.balanceUSD
            merged.monetaryKind = .balance
        }
        merged.note = [key?.note, credits?.note].compactMap { $0 }.joined(separator: " · ")
        return merged
    }

    static func mergeOpenRouterAccount(api: AccountQuota?, portal: AccountQuota?) -> AccountQuota? {
        guard api != nil || portal != nil else { return nil }
        var merged = api ?? portal!
        merged.service = .openRouter
        merged.monthlySpendUSD = portal?.monthlySpendUSD
        merged.monthlySpendBRL = portal?.monthlySpendBRL
        merged.spendPeriod = portal?.spendPeriod
        merged.spendWindowStart = portal?.spendWindowStart
        merged.spendWindowEnd = portal?.spendWindowEnd
        merged.balanceUSD = api?.balanceUSD
        merged.monetaryUSD = merged.balanceUSD ?? merged.monthlySpendUSD
        merged.monetaryKind = merged.balanceUSD != nil ? .balance : (merged.monthlySpendUSD != nil ? .spend : nil)
        merged.mergeOrigins(api: api, portal: portal)
        merged.reconcile(api: api, portal: portal)
        var details = [api?.note, portal?.note].compactMap { $0 }
        if merged.monthlySpendUSD == nil {
            details.append("Connect the OpenRouter portal to read total account spend for the last 30 days")
        }
        merged.note = details.joined(separator: " · ")
        return merged
    }

    static func fetchOpenRouter(key: String, session: URLSession = .shared) async -> AccountQuota? {
        async let keyData = getJSON(
            url: URL(string: "https://openrouter.ai/api/v1/key")!,
            headers: ["Authorization": "Bearer \(key)"],
            session: session
        )
        async let creditsData = getJSON(
            url: URL(string: "https://openrouter.ai/api/v1/credits")!,
            headers: ["Authorization": "Bearer \(key)"],
            session: session
        )
        let parsedKey = await keyData.flatMap(openRouterQuota(data:))
        let parsedCredits = await creditsData.flatMap(openRouterCreditsQuota(data:))
        return mergeOpenRouter(key: parsedKey, credits: parsedCredits)
    }

    /// X's usage endpoint exposes the app/project's monthly Post consumption
    /// and cap. It is a read-only monitoring endpoint, not a user identity
    /// request, so an app bearer token is the correct credential.
    static func xTwitterUsage(data: Data) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["data"] as? [String: Any]
        else { return nil }
        let cap = numericValue(body["project_cap"])
        let directUsage = numericValue(body["project_usage"])
        let projectID = body["project_id"] as? String
        let dailyUsage: Double? = {
            if let items = body["daily_project_usage"] as? [[String: Any]] {
                return items.compactMap { item in
                    numericValue(item["usage"]) ?? numericValue(item["tweets_consumed"])
                }.reduce(0, +)
            }
            if let daily = body["daily_project_usage"] as? [String: Any],
               let entries = daily["usage"] as? [[String: Any]] {
                return entries.compactMap { numericValue($0["usage"]) ?? numericValue($0["tweets_consumed"]) }.reduce(0, +)
            }
            return nil
        }()
        guard let used = directUsage ?? dailyUsage else { return nil }
        let percent = cap.flatMap { $0 > 0 ? min(max(used / $0 * 100, 0), 100) : nil }
        return AccountQuota(
            service: .xTwitter,
            usedPercent: percent,
            resetsAt: nil,
            note: cap.map { "X API: \(Int(used)) of \(Int($0)) Posts consumed in the last 30 days" } ?? "X API: \(Int(used)) Posts consumed in the last 30 days",
            cycleUsed: used,
            cycleLimit: cap,
            cycleUnit: "posts",
            billingScopeID: projectID.map { "x-project:\($0)" }
        )
    }

    static func fetchXTwitter(bearerToken: String, session: URLSession = .shared) async -> AccountQuota? {
        var components = URLComponents(string: "https://api.x.com/2/usage/tweets")
        components?.queryItems = [
            URLQueryItem(name: "days", value: "30"),
            URLQueryItem(name: "usage.fields", value: "project_usage,project_cap,cap_reset_day,daily_project_usage,daily_client_app_usage"),
        ]
        guard let url = components?.url,
              let data = await getJSON(url: url, headers: ["Authorization": "Bearer \(bearerToken)"], session: session)
        else { return nil }
        return xTwitterUsage(data: data)
    }

    static func mergeXTwitter(api: AccountQuota?, portal: AccountQuota?) -> AccountQuota? {
        guard api != nil || portal != nil else { return nil }
        var merged = api ?? portal!
        merged.monthlySpendUSD = portal?.monthlySpendUSD
        merged.monthlySpendBRL = portal?.monthlySpendBRL
        merged.spendPeriod = portal?.spendPeriod
        merged.spendWindowStart = portal?.spendWindowStart
        merged.spendWindowEnd = portal?.spendWindowEnd
        merged.balanceUSD = portal?.balanceUSD
        merged.monetaryUSD = merged.balanceUSD ?? merged.monthlySpendUSD
        merged.monetaryKind = merged.balanceUSD != nil ? .balance : (merged.monthlySpendUSD != nil ? .spend : nil)
        // Financial data belongs to the authenticated Console billing account,
        // which may differ even when two Bearer Tokens report the same project.
        merged.billingScopeID = portal?.billingScopeID ?? api?.billingScopeID
        merged.mergeOrigins(api: api, portal: portal)
        merged.reconcile(api: api, portal: portal)
        merged.note = [api?.note, portal?.note].compactMap { $0 }.joined(separator: " · ")
        return merged
    }

    /// twitterapi.io reports the remaining prepaid balance in service credits.
    /// Its published fixed conversion is 100,000 credits per USD.
    static func twitterAPIIOBalance(data: Data) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let credits = numericValue(root["recharge_credits"])
        else { return nil }
        let balanceUSD = max(credits, 0) / 100_000
        return AccountQuota(
            service: .twitterAPI,
            usedPercent: nil,
            resetsAt: nil,
            note: String(
                format: "twitterapi.io: %.0f credits remaining · %.2f USD equivalent",
                locale: Locale(identifier: "en_US_POSIX"),
                credits,
                balanceUSD
            ),
            monetaryUSD: balanceUSD,
            monetaryKind: .balance,
            balanceUSD: balanceUSD,
            cycleUsed: credits,
            cycleUnit: "créditos restantes"
        )
    }

    static func fetchTwitterAPIIO(key: String, session: URLSession = .shared) async -> AccountQuota? {
        guard let data = await getJSON(
            url: URL(string: "https://api.twitterapi.io/oapi/my/info")!,
            headers: ["X-API-Key": key],
            session: session
        ) else { return nil }
        return twitterAPIIOBalance(data: data)
    }

    static func mergeTwitterAPIIO(api: AccountQuota?, portal: AccountQuota?) -> AccountQuota? {
        guard api != nil || portal != nil else { return nil }
        var merged = api ?? portal!
        merged.monthlySpendUSD = portal?.monthlySpendUSD
        merged.monthlySpendBRL = portal?.monthlySpendBRL
        merged.spendPeriod = portal?.spendPeriod
        merged.spendWindowStart = portal?.spendWindowStart
        merged.spendWindowEnd = portal?.spendWindowEnd
        merged.balanceUSD = api?.balanceUSD ?? portal?.balanceUSD
        merged.monetaryUSD = merged.balanceUSD ?? merged.monthlySpendUSD
        merged.monetaryKind = merged.balanceUSD != nil ? .balance : (merged.monthlySpendUSD != nil ? .spend : nil)
        merged.cycleUsed = portal?.cycleUsed ?? api?.cycleUsed
        merged.cycleUnit = portal?.cycleUnit ?? api?.cycleUnit
        merged.mergeOrigins(api: api, portal: portal)
        merged.reconcile(api: api, portal: portal)
        merged.note = [api?.note, portal?.note].compactMap { $0 }.joined(separator: " · ")
        return merged
    }

    /// xAI represents prepaid credit balance as signed USD cents. Purchases
    /// are negative in the API response, hence negating yields available USD.
    static func xAIPrepaidBalance(data: Data, usageData: Data? = nil, window: DateInterval? = nil) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let total = root["total"] as? [String: Any],
              let cents = numericValue(total["val"])
        else { return nil }
        let balance = max(-cents / 100, 0)
        let monthlySpend = usageData.flatMap { data -> Double? in
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let series = root["timeSeries"] as? [[String: Any]] else { return nil }
            let points = series.flatMap { $0["dataPoints"] as? [[String: Any]] ?? [] }
            let values = points.compactMap { $0["values"] as? [Any] }.flatMap { $0 }
            return values
                .compactMap(numericValue)
                .reduce(0, +)
        }
        var details: [String] = []
        if let monthlySpend {
            details.append(String(
                format: "spend last 30 days: %.2f USD",
                locale: Locale(identifier: "en_US_POSIX"),
                monthlySpend
            ))
        }
        details.append(String(
            format: "prepaid balance: %.2f USD",
            locale: Locale(identifier: "en_US_POSIX"),
            balance
        ))
        return AccountQuota(
            service: .xAI,
            usedPercent: nil,
            resetsAt: nil,
            note: "xAI \(details.joined(separator: " · "))",
            monetaryUSD: balance,
            monetaryKind: .balance,
            monthlySpendUSD: monthlySpend,
            spendPeriod: monthlySpend == nil || window == nil ? nil : .rolling30Days,
            spendWindowStart: monthlySpend == nil ? nil : window?.start,
            spendWindowEnd: monthlySpend == nil ? nil : window?.end,
            balanceUSD: balance
        )
    }

    static func fetchXAI(managementKey: String, now: Date = Date(), session: URLSession = .shared) async -> AccountQuota? {
        let headers = ["Authorization": "Bearer \(managementKey)"]
        guard let validationURL = URL(string: "https://management-api.x.ai/auth/management-keys/validation"),
              let validationData = await getJSON(url: validationURL, headers: headers, session: session),
              let validation = try? JSONSerialization.jsonObject(with: validationData) as? [String: Any],
              let teamID = (validation["teamId"] as? String) ?? (validation["scopeId"] as? String),
              let encodedTeamID = teamID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let balanceURL = URL(string: "https://management-api.x.ai/v1/billing/teams/\(encodedTeamID)/prepaid/balance"),
              let balanceData = await getJSON(url: balanceURL, headers: headers, session: session)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let range = APIAccountSpendWindow.rolling30Days(endingAt: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let analytics: [String: Any] = [
            "analyticsRequest": [
                "timeRange": [
                    "startTime": formatter.string(from: range.start),
                    "endTime": formatter.string(from: range.end),
                    "timezone": "Etc/GMT",
                ],
                "timeUnit": "TIME_UNIT_DAY",
                "values": [["name": "usd", "aggregation": "AGGREGATION_SUM"]],
                "groupBy": [],
                "filters": [],
            ],
        ]
        let usageURL = URL(string: "https://management-api.x.ai/v1/billing/teams/\(encodedTeamID)/usage")!
        let usageData = await postJSON(url: usageURL, headers: headers, body: analytics, session: session)
        return xAIPrepaidBalance(data: balanceData, usageData: usageData, window: range)
    }

    /// Contract for internal or vendor-supplied read-only metric endpoints:
    /// `{ "used_percent": 42, "resets_at": "ISO-8601", "note": "..." }`.
    /// `remaining_percent` is also accepted. Unknown fields are ignored.
    static func standardQuota(data: Data, service: APIServiceID) -> AccountQuota? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let used = body["used_percent"] as? Double
        let remaining = body["remaining_percent"] as? Double
        guard let rawPercent = used ?? remaining.map({ 100 - $0 }) else { return nil }
        let reset = (body["resets_at"] as? String).flatMap(Timestamps.parseISO8601)
        let note = (body["note"] as? String) ?? "\(service.displayName): official read-only metric"
        return AccountQuota(
            service: service,
            usedPercent: min(max(rawPercent, 0), 100),
            resetsAt: reset,
            note: note
        )
    }

    static func fetchStandardQuota(endpoint: String, key: String, service: APIServiceID, session: URLSession = .shared) async -> AccountQuota? {
        guard let url = URL(string: endpoint), url.scheme == "https",
              let data = await getJSON(url: url, headers: ["Authorization": "Bearer \(key)"], session: session)
        else { return nil }
        return standardQuota(data: data, service: service)
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let text = value as? String { return Double(text) }
        return nil
    }

    /// Matches the latest Cloud Monitoring allocation-usage point to its
    /// corresponding quota-limit point. The response is deliberately handled
    /// generically because Google Cloud quota names vary by enabled service.
    static func googleCloudQuota(usageData: Data, limitData: Data) -> AccountQuota? {
        guard let usageRoot = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any],
              let limitRoot = try? JSONSerialization.jsonObject(with: limitData) as? [String: Any]
        else { return nil }

        func series(_ root: [String: Any]) -> [(String, Double)] {
            (root["timeSeries"] as? [[String: Any]] ?? []).compactMap { item in
                let metricLabels = (item["metric"] as? [String: Any])?["labels"] as? [String: Any] ?? [:]
                let resourceLabels = (item["resource"] as? [String: Any])?["labels"] as? [String: Any] ?? [:]
                let quota = metricLabels["quota_metric"] as? String ?? ""
                guard !quota.isEmpty,
                      let point = (item["points"] as? [[String: Any]])?.first,
                      let value = point["value"] as? [String: Any]
                else { return nil }
                let number = numericValue(value["int64Value"]) ?? numericValue(value["doubleValue"])
                guard let number else { return nil }
                let service = resourceLabels["service"] as? String ?? ""
                let location = resourceLabels["location"] as? String ?? ""
                return ("\(service)|\(location)|\(quota)", number)
            }
        }

        let usages = series(usageRoot)
        let limits = series(limitRoot)
        var worst: (key: String, percent: Double)?
        for usage in usages {
            // A quota metric can have several regional limits. Choosing the
            // smallest matching limit is conservative and never understates a
            // potential exhaustion risk.
            guard let limit = limits.filter({ $0.0 == usage.0 }).map(\.1).min(), limit > 0 else { continue }
            let percent = min(max(usage.1 / limit * 100, 0), 100)
            if worst.map({ percent > $0.percent }) ?? true {
                worst = (usage.0, percent)
            }
        }
        guard let worst else {
            return AccountQuota(
                service: .gemini,
                usedPercent: nil,
                resetsAt: nil,
                note: "Google Cloud connected · no allocation quota activity in the current window"
            )
        }
        let metric = worst.key.split(separator: "|").last.map(String.init) ?? "quota"
        return AccountQuota(
            service: .gemini,
            usedPercent: worst.percent,
            resetsAt: nil,
            note: String(format: "Google Cloud highest allocation quota: %@ (%.0f%% used)", metric, worst.percent)
        )
    }

    static func fetchGoogleCloud(projectID: String, oauthToken: String, now: Date = Date(), session: URLSession = .shared) async -> AccountQuota? {
        guard let encodedProject = projectID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        let end = now.ISO8601Format()
        let start = now.addingTimeInterval(-10 * 60).ISO8601Format()
        let headers = ["Authorization": "Bearer \(oauthToken)"]
        let filters = [
            "metric.type=\"serviceruntime.googleapis.com/quota/allocation/usage\" resource.type=\"consumer_quota\"",
            "metric.type=\"serviceruntime.googleapis.com/quota/limit\" resource.type=\"consumer_quota\"",
        ]
        let urls = filters.compactMap { filter -> URL? in
            var components = URLComponents(string: "https://monitoring.googleapis.com/v3/projects/\(encodedProject)/timeSeries")
            components?.queryItems = [
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "interval.startTime", value: start),
                URLQueryItem(name: "interval.endTime", value: end),
                URLQueryItem(name: "view", value: "FULL"),
            ]
            return components?.url
        }
        guard urls.count == 2,
              let usage = await getJSON(url: urls[0], headers: headers, session: session),
              let limits = await getJSON(url: urls[1], headers: headers, session: session)
        else { return nil }
        return googleCloudQuota(usageData: usage, limitData: limits)
    }

    static func mergeGoogleCloud(api: AccountQuota?, portal: AccountQuota?) -> AccountQuota? {
        guard api != nil || portal != nil else { return nil }
        var merged = api ?? portal!
        merged.monthlySpendUSD = portal?.monthlySpendUSD
        merged.monthlySpendBRL = portal?.monthlySpendBRL
        merged.spendPeriod = portal?.spendPeriod
        merged.spendWindowStart = portal?.spendWindowStart
        merged.spendWindowEnd = portal?.spendWindowEnd
        merged.monetaryUSD = portal?.monthlySpendUSD
        merged.monetaryKind = portal?.monthlySpendUSD == nil ? nil : .spend
        merged.billingScopeID = portal?.billingScopeID ?? api?.billingScopeID
        merged.mergeOrigins(api: api, portal: portal)
        merged.reconcile(api: api, portal: portal)
        merged.note = [api?.note, portal?.note].compactMap { $0 }.joined(separator: " · ")
        return merged
    }
}

/// Safe first stage for external account monitoring. It is opt-in and does
/// not discover, read, or send credentials. A later credential setup attaches
/// a read-only account endpoint to each selected service.
struct APIAccountProvider: UsageProvider {
    let id = ProviderID.apiAccounts
    let capabilities: ProviderCapabilities = [.sessionPercent, .resetSchedule]
    private let cache = APIAccountSnapshotCache()

    func detectInstallation() -> ProviderInstallation {
        .installed(dataPath: "Keychain (opt-in API account monitors)")
    }

    func invalidateCache() async {
        await cache.clear()
    }

    func fetchSnapshot(settings: AppSettings) async throws -> UsageSnapshot {
        guard settings.apiAccountMonitoringEnabled else {
            return UsageSnapshot(
                provider: id,
                health: .noData,
                note: "API account monitoring is off"
            )
        }

        let legacyAccounts = settings.monitoredAPIServices.sorted { $0.displayName < $1.displayName }.map { service in
            APIAccount(
                service: service,
                identifier: settings.apiAccountIdentifiers[service] ?? "",
                keychainAccount: service.rawValue
            )
        }
        let selected = (settings.apiAccounts.isEmpty ? legacyAccounts : settings.apiAccounts)
            .filter(\.enabled)
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        guard !selected.isEmpty else {
            return UsageSnapshot(
                provider: id,
                health: .noData,
                note: "Select one or more API accounts to monitor"
            )
        }

        let fingerprint = selected.map {
            "\($0.id.uuidString):\($0.service.rawValue):\($0.identifier):\($0.credentialService?.rawValue ?? "legacy"):\($0.credentialRevision?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: ",")
        if let cached = await cache.fresh(fingerprint: fingerprint) {
            return cached
        }
        let cacheRevision = await cache.currentRevision()

        let reports = await withTaskGroup(of: (APIAccount, AccountQuota?).self, returning: [(APIAccount, AccountQuota?)].self) { group in
            for account in selected {
                group.addTask { (account, await Self.fetchQuota(for: account)) }
            }
            var collected: [(APIAccount, AccountQuota?)] = []
            for await report in group { collected.append(report) }
            return collected
        }

        var quotas: [AccountQuota] = []
        var accountUsage: [APIAccountUsage] = []
        for (account, report) in reports {
            if var quota = report {
                quota.note = "\(account.label): \(quota.note)"
                quotas.append(quota)
                accountUsage.append(Self.makeUsage(for: account, quota: quota))
            } else {
                accountUsage.append(Self.makeUsage(for: account, quota: nil))
            }
        }
        accountUsage.sort { left, right in
            guard let lhs = selected.firstIndex(where: { $0.id == left.accountID }),
                  let rhs = selected.firstIndex(where: { $0.id == right.accountID })
            else { return left.label < right.label }
            return lhs < rhs
        }
        let waiting = accountUsage.filter { $0.readStatus != .updated && $0.readStatus != .partial }

        guard !quotas.isEmpty else {
            let names = waiting.map(\.label).joined(separator: ", ")
            return UsageSnapshot(
                provider: id,
                health: .noData,
                note: "Selected: \(names). Add read-only credentials in Keychain to begin monitoring.",
                accountUsage: accountUsage
            )
        }
        let mostUsed = quotas.compactMap { quota in quota.usedPercent.map { (quota, $0) } }
            .max { $0.1 < $1.1 }?.0
        let notes = quotas.map(\.note).joined(separator: " · ")
        let snapshot = UsageSnapshot(
            provider: id,
            health: waiting.isEmpty ? .ok : .degraded,
            session: mostUsed.map { SessionUsage(resetsAt: $0.resetsAt, usedPercent: $0.usedPercent) },
            note: notes,
            accountUsage: accountUsage
        )
        await cache.store(snapshot, fingerprint: fingerprint, ifRevision: cacheRevision)
        return snapshot
    }

    func fetchAccountUsage(for account: APIAccount) async -> APIAccountUsage {
        await cache.clear()
        var quota = await Self.fetchQuota(for: account)
        if var report = quota {
            report.note = "\(account.label): \(report.note)"
            quota = report
        }
        return Self.makeUsage(for: account, quota: quota)
    }

    private static func makeUsage(for account: APIAccount, quota: AccountQuota?) -> APIAccountUsage {
        let now = Date()
        guard let quota else {
            let status = failureStatus(for: account)
            return APIAccountUsage(
                accountID: account.id,
                label: account.label,
                service: account.service,
                capturedAt: now,
                usedPercent: nil,
                resetsAt: nil,
                summary: failureSummary(status),
                readStatus: status
            )
        }
        return APIAccountUsage(
            accountID: account.id,
            label: account.label,
            service: account.service,
            capturedAt: now,
            usedPercent: quota.usedPercent,
            resetsAt: quota.resetsAt,
            summary: quota.note,
            monetaryUSD: quota.monetaryUSD,
            monetaryKind: quota.monetaryKind,
            monthlySpendUSD: quota.monthlySpendUSD,
            monthlySpendBRL: quota.monthlySpendBRL,
            spendPeriod: quota.spendPeriod,
            spendWindowStart: quota.spendWindowStart,
            spendWindowEnd: quota.spendWindowEnd,
            balanceUSD: quota.balanceUSD,
            rechargeUSD: quota.rechargeUSD,
            rechargeBRL: quota.rechargeBRL,
            monthlyPlanUSD: quota.monthlyPlanUSD,
            monthlyPlanBRL: quota.monthlyPlanBRL,
            balanceBRL: quota.balanceBRL,
            planName: quota.planName,
            seatCount: quota.seatCount,
            cycleUsed: quota.cycleUsed,
            cycleLimit: quota.cycleLimit,
            cycleRemaining: quota.cycleRemaining,
            cycleOverage: quota.cycleOverage,
            cycleUnit: quota.cycleUnit,
            billingScopeID: quota.billingScopeID,
            readStatus: readStatus(for: account, quota: quota),
            origins: quota.origins,
            verificationFindings: quota.verificationFindings
        )
    }

    private static func readStatus(for account: APIAccount, quota: AccountQuota) -> APIAccountReadStatus {
        if !quota.verificationFindings.isEmpty {
            return .partial
        }
        let complete: Bool
        switch account.service {
        case .openAI, .deepSeek, .openRouter, .twitterAPI,
             .xTwitter, .xTwitterAccount1, .xTwitterAccount2:
            complete = quota.monthlySpendUSD != nil && quota.balanceUSD != nil
        case .gemini:
            complete = quota.monthlySpendUSD != nil || quota.monthlySpendBRL != nil
        case .anthropicAPI:
            complete = quota.monthlySpendUSD != nil
        case .xAI:
            complete = quota.monthlySpendUSD != nil && quota.balanceUSD != nil
        case .elevenLabs, .firecrawl:
            complete = quota.cycleLimit != nil
        case .anthropicConsole, .chatGPTSubscription, .googleSubscription, .firecrawlSubscription:
            complete = quota.monthlyPlanUSD != nil || quota.monthlyPlanBRL != nil
        default:
            complete = quota.usedPercent != nil
                || quota.monthlySpendUSD != nil
                || quota.monthlySpendBRL != nil
                || quota.balanceUSD != nil
        }
        return complete ? .updated : .partial
    }

    private static func failureStatus(for account: APIAccount) -> APIAccountReadStatus {
        if account.service.isSubscriptionService {
            return .needsLogin
        }
        if account.service == .gemini {
            return account.identifier.isEmpty ? .needsCredential : .unavailable
        }
        if account.service == .anthropicAPI,
           APIAccountCredentialStore.key(for: account) == nil {
            return .needsLogin
        }
        return APIAccountCredentialStore.key(for: account) == nil
            ? .needsCredential
            : .unavailable
    }

    private static func failureSummary(_ status: APIAccountReadStatus) -> String {
        switch status {
        case .needsCredential:
            "Credencial de leitura ausente"
        case .needsLogin:
            "Login web ausente ou expirado"
        case .unavailable:
            "Fonte oficial indisponível ou resposta não reconhecida"
        case .partial:
            "Leitura parcial"
        case .stale:
            "Leitura desatualizada"
        case .updated:
            "Atualizado"
        }
    }

    private static func fetchQuota(for account: APIAccount) async -> AccountQuota? {
        if account.service == .anthropicConsole {
            #if os(macOS)
            return (await AnthropicConsoleReader(accountID: account.id).fetchQuota())?
                .tagged(.officialPortal)
            #else
            return nil
            #endif
        }
        if account.service == .chatGPTSubscription {
            #if os(macOS)
            return (await ChatGPTSubscriptionReader(accountID: account.id).fetchQuota())?
                .tagged(.officialPortal)
            #else
            return nil
            #endif
        }
        if account.service == .googleSubscription {
            #if os(macOS)
            return (await GoogleSubscriptionReader(accountID: account.id).fetchQuota())?
                .tagged(.officialPortal)
            #else
            return nil
            #endif
        }
        if account.service == .firecrawlSubscription {
            #if os(macOS)
            return (await FirecrawlSubscriptionReader(accountID: account.id).fetchQuota())?
                .tagged(.officialPortal)
            #else
            return nil
            #endif
        }
        if account.service == .anthropicAPI {
            let key = APIAccountCredentialStore.key(for: account)
            #if os(macOS)
            async let portal = AnthropicAPIConsoleReader(accountID: account.id).fetchQuota()
            let official: AccountQuota?
            if let key {
                official = (await APIAccountProbe.fetchAnthropicCost(adminKey: key))?
                    .tagged(.officialAPI)
            } else {
                official = nil
            }
            return (await portal)?.tagged(.officialPortal) ?? official
            #else
            guard let key else { return nil }
            return (await APIAccountProbe.fetchAnthropicCost(adminKey: key))?
                .tagged(.officialAPI)
            #endif
        }
        if account.service == .gemini {
            guard !account.identifier.isEmpty,
                  let token = await GoogleCloudCredentialProvider.accessToken(
                    fallback: APIAccountCredentialStore.key(for: account)
                  )
            else { return nil }
            async let apiResult = APIAccountProbe.fetchGoogleCloud(
                projectID: account.identifier,
                oauthToken: token
            )
            #if os(macOS)
            let rate = UserDefaults.standard
                .string(forKey: "agentmeter.subscriptions.v1.brl-per-usd")
                .flatMap(Double.init)
            let api = (await apiResult)?.tagged(.officialAPI)
            let portal = (await GoogleAIStudioConsoleReader(
                accountID: account.id,
                projectID: account.identifier
            ).fetchQuota(brlPerUSD: rate))?.tagged(.officialPortal)
            return APIAccountProbe.mergeGoogleCloud(api: api, portal: portal)
            #else
            return (await apiResult)?.tagged(.officialAPI)
            #endif
        }
        guard let key = APIAccountCredentialStore.key(for: account) else { return nil }
        switch account.service {
        case .anthropicAPI:
            return nil
        case .elevenLabs:
            return (await APIAccountProbe.fetchElevenLabs(key: key))?.tagged(.officialAPI)
        case .firecrawl:
            return (await APIAccountProbe.fetchFirecrawl(key: key))?.tagged(.officialAPI)
        case .deepSeek:
            async let apiResult = APIAccountProbe.fetchDeepSeek(key: key)
            #if os(macOS)
            let api = (await apiResult)?.tagged(.officialAPI)
            let console = (await DeepSeekConsoleReader(accountID: account.id).fetchQuota())?
                .tagged(.officialPortal)
            return APIAccountProbe.mergeDeepSeek(api: api, console: console)
            #else
            return (await apiResult)?.tagged(.officialAPI)
            #endif
        case .openAI:
            async let apiResult = APIAccountProbe.fetchOpenAI(key: key)
            #if os(macOS)
            let api = (await apiResult)?.tagged(.officialAPI)
            let portal = (await OpenAIConsoleReader(accountID: account.id).fetchQuota())?
                .tagged(.officialPortal)
            return APIAccountProbe.mergeOpenAI(api: api, portal: portal)
            #else
            return (await apiResult)?.tagged(.officialAPI)
            #endif
        case .heyGen:
            return (await APIAccountProbe.fetchHeyGen(key: key))?.tagged(.officialAPI)
        case .twilio:
            return account.identifier.isEmpty
                ? nil
                : (await APIAccountProbe.fetchTwilio(accountSID: account.identifier, apiKey: key))?
                    .tagged(.officialAPI)
        case .xAI:
            return (await APIAccountProbe.fetchXAI(managementKey: key))?.tagged(.officialAPI)
        case .openRouter:
            async let apiResult = APIAccountProbe.fetchOpenRouter(key: key)
            #if os(macOS)
            let api = (await apiResult)?.tagged(.officialAPI)
            let portal = (await OpenRouterConsoleReader(accountID: account.id).fetchQuota())?
                .tagged(.officialPortal)
            return APIAccountProbe.mergeOpenRouterAccount(api: api, portal: portal)
            #else
            return (await apiResult)?.tagged(.officialAPI)
            #endif
        case .gemini:
            return nil
        case .xTwitter, .xTwitterAccount1, .xTwitterAccount2:
            async let apiResult = APIAccountProbe.fetchXTwitter(bearerToken: key)
            #if os(macOS)
            let api = (await apiResult)?.tagged(.officialAPI)
            let portal = (await XDeveloperConsoleReader(accountID: account.id).fetchQuota())?
                .tagged(.officialPortal)
            return APIAccountProbe.mergeXTwitter(api: api, portal: portal)
            #else
            return (await apiResult)?.tagged(.officialAPI)
            #endif
        case .twitterAPI:
            async let apiResult = APIAccountProbe.fetchTwitterAPIIO(key: key)
            #if os(macOS)
            let api = (await apiResult)?.tagged(.officialAPI)
            let portal = (await TwitterAPIIOConsoleReader(accountID: account.id).fetchQuota())?
                .tagged(.officialPortal)
            return APIAccountProbe.mergeTwitterAPIIO(api: api, portal: portal)
            #else
            return (await apiResult)?.tagged(.officialAPI)
            #endif
        case .infoSimples, .brAPI, .logoDev, .higgsfield, .artificialAnalysis, .swen:
            return account.identifier.isEmpty
                ? nil
                : (await APIAccountProbe.fetchStandardQuota(
                    endpoint: account.identifier,
                    key: key,
                    service: account.service
                ))?.tagged(.officialAPI)
        case .anthropicConsole, .chatGPTSubscription, .googleSubscription, .firecrawlSubscription:
            return nil
        }
    }
}
