import XCTest
@testable import NotchAgent

final class APIAccountProviderTests: XCTestCase {
    func testGoogleCloudCredentialNormalizesManualFallbackWithoutLoggingIt() {
        XCTAssertEqual(
            GoogleCloudCredentialProvider.normalizedToken("  access-token\n"),
            "access-token"
        )
        XCTAssertNil(GoogleCloudCredentialProvider.normalizedToken(" \n "))
        XCTAssertNil(GoogleCloudCredentialProvider.normalizedToken(nil))
    }

    func testFinancialSummaryUsesConsumedPlusRemainingAsAvailable() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = APIAccountUsage(
            accountID: UUID(),
            label: "Conta",
            service: .xTwitter,
            usedPercent: nil,
            resetsAt: nil,
            summary: "Financeiro",
            monthlySpendUSD: 82.4,
            spendPeriod: .rolling30Days,
            spendWindowStart: end.addingTimeInterval(-APIAccountSpendWindow.duration),
            spendWindowEnd: end,
            balanceUSD: 98.37
        )

        let summary = APIAccountFinancialSummary(usage: usage)

        XCTAssertEqual(summary.consumedUSD, 82.4)
        XCTAssertEqual(summary.remainingUSD, 98.37)
        XCTAssertEqual(summary.availableUSD ?? -1, 180.77, accuracy: 0.000_001)
        XCTAssertTrue(summary.isComplete)
    }

    func testFinancialSummaryDoesNotInventMissingValues() {
        let usage = APIAccountUsage(
            accountID: UUID(),
            label: "Conta",
            service: .openAI,
            usedPercent: nil,
            resetsAt: nil,
            summary: "Saldo",
            monetaryUSD: 42.75,
            monetaryKind: .balance
        )

        let summary = APIAccountFinancialSummary(usage: usage)

        XCTAssertNil(summary.consumedUSD)
        XCTAssertEqual(summary.remainingUSD, 42.75)
        XCTAssertNil(summary.availableUSD)
        XCTAssertFalse(summary.isComplete)
    }

    func testFinancePresentationUsesThreeBRLColumnsAndGoogleWindow() {
        let account = APIAccount(service: .gemini)
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = APIAccountUsage(
            accountID: account.id,
            label: account.label,
            service: account.service,
            usedPercent: nil,
            resetsAt: nil,
            summary: "Official",
            monthlySpendUSD: 10,
            spendPeriod: .rolling28Days,
            spendWindowStart: end.addingTimeInterval(-28 * 24 * 60 * 60),
            spendWindowEnd: end,
            balanceUSD: 20,
            monthlyPlanUSD: 5,
            origins: APIAccountFieldOrigins(
                spend: .officialPortal,
                balance: .officialAPI,
                plan: .officialPortal
            )
        )

        let finance = APIAccountFinancePresentation(
            account: account,
            usage: usage,
            brlPerUSD: Decimal(string: "5")
        )

        XCTAssertEqual(finance.spend.amountBRL, Decimal(string: "50"))
        XCTAssertEqual(finance.balance.amountBRL, Decimal(string: "100"))
        XCTAssertEqual(finance.plan.amountBRL, Decimal(string: "25"))
        XCTAssertEqual(finance.spendLabel, "GASTO 28 DIAS")
        XCTAssertEqual(finance.spend.confidence, .officialPortal)
    }

    func testFinancePresentationProportionalizesOfficialQuotaWithoutCallingItOfficialSpend() {
        let account = APIAccount(
            service: .firecrawl,
            monthlyPlanBRL: Decimal(string: "508")
        )
        let usage = APIAccountUsage(
            accountID: account.id,
            label: account.label,
            service: account.service,
            usedPercent: 50,
            resetsAt: nil,
            summary: "Official quota",
            cycleUsed: 50_000,
            cycleLimit: 100_000,
            cycleRemaining: 50_000,
            cycleUnit: "credits",
            origins: APIAccountFieldOrigins(quota: .officialAPI)
        )

        let finance = APIAccountFinancePresentation(
            account: account,
            usage: usage,
            brlPerUSD: nil
        )

        XCTAssertEqual(finance.spend.amountBRL, Decimal(string: "254"))
        XCTAssertEqual(finance.balance.amountBRL, Decimal(string: "254"))
        XCTAssertEqual(finance.plan.amountBRL, Decimal(string: "508"))
        XCTAssertEqual(finance.spend.confidence, .derived)
        XCTAssertEqual(finance.balance.confidence, .derived)
        XCTAssertEqual(finance.plan.confidence, .manual)
    }

    func testAccountUsagePersistsSeparatedMoneyAndProvenance() throws {
        let usage = APIAccountUsage(
            accountID: UUID(),
            label: "Conta",
            service: .openAI,
            usedPercent: nil,
            resetsAt: nil,
            summary: "Oficial",
            monthlySpendUSD: 12,
            monthlySpendBRL: Decimal(string: "61.44"),
            balanceUSD: 40,
            rechargeUSD: 50,
            readStatus: .updated,
            origins: APIAccountFieldOrigins(
                spend: .officialAPI,
                balance: .officialPortal,
                recharge: .officialPortal
            )
        )

        let restored = try JSONDecoder().decode(
            APIAccountUsage.self,
            from: JSONEncoder().encode(usage)
        )

        XCTAssertEqual(restored.monthlySpendUSD, 12)
        XCTAssertEqual(restored.monthlySpendBRL, Decimal(string: "61.44"))
        XCTAssertEqual(restored.balanceUSD, 40)
        XCTAssertEqual(restored.rechargeUSD, 50)
        XCTAssertEqual(restored.readStatus, .updated)
        XCTAssertEqual(restored.origins?.spend, .officialAPI)
        XCTAssertEqual(restored.origins?.balance, .officialPortal)
    }

    func testAccountUsageDecodesSnapshotsCreatedBeforeVerificationFields() throws {
        let usage = APIAccountUsage(
            accountID: UUID(),
            label: "Legacy",
            service: .openAI,
            usedPercent: nil,
            resetsAt: nil,
            summary: "Legacy snapshot"
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(usage)) as? [String: Any]
        )
        json.removeValue(forKey: "verificationFindings")
        json.removeValue(forKey: "monthlySpendBRL")

        let restored = try JSONDecoder().decode(
            APIAccountUsage.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        XCTAssertNil(restored.verificationFindings)
        XCTAssertNil(restored.monthlySpendBRL)
    }

    func testOfficialSourceComparatorAppliesMonetaryTolerance() {
        let api = AccountQuota(
            service: .deepSeek,
            usedPercent: nil,
            resetsAt: nil,
            note: "API",
            balanceUSD: 10
        )
        let withinTolerance = AccountQuota(
            service: .deepSeek,
            usedPercent: nil,
            resetsAt: nil,
            note: "Portal",
            balanceUSD: 10.019
        )
        let outsideTolerance = AccountQuota(
            service: .deepSeek,
            usedPercent: nil,
            resetsAt: nil,
            note: "Portal",
            balanceUSD: 10.03
        )

        XCTAssertTrue(APIAccountOfficialComparator.findings(
            api: api,
            portal: withinTolerance
        ).isEmpty)
        XCTAssertEqual(
            APIAccountOfficialComparator.findings(api: api, portal: outsideTolerance),
            ["balance_usd_source_mismatch"]
        )
    }

    func testOfficialSourceMismatchPropagatesIntoAudit() throws {
        let api = AccountQuota(
            service: .deepSeek,
            usedPercent: nil,
            resetsAt: nil,
            note: "API",
            balanceUSD: 10
        )
        let portal = AccountQuota(
            service: .deepSeek,
            usedPercent: nil,
            resetsAt: nil,
            note: "Portal",
            balanceUSD: 11
        )
        let merged = try XCTUnwrap(APIAccountProbe.mergeDeepSeek(api: api, console: portal))
        let account = APIAccount(service: .deepSeek)
        let usage = APIAccountUsage(
            accountID: account.id,
            label: account.label,
            service: account.service,
            usedPercent: nil,
            resetsAt: nil,
            summary: merged.note,
            balanceUSD: merged.balanceUSD,
            readStatus: .partial,
            origins: APIAccountFieldOrigins(balance: .officialAPI),
            verificationFindings: merged.verificationFindings
        )

        let audit = APIAccountIntegrityAuditor.audit(account: account, usage: usage)

        XCTAssertEqual(merged.verificationFindings, ["balance_usd_source_mismatch"])
        XCTAssertEqual(audit.outcome, .invalid)
        XCTAssertTrue(audit.findings.contains("balance_usd_source_mismatch"))
    }

    func testAPIAccountOrderingMovesForwardAndBackward() {
        let first = APIAccount(service: .openAI, label: "First")
        let second = APIAccount(service: .deepSeek, label: "Second")
        let third = APIAccount(service: .openRouter, label: "Third")

        let movedForward = APIAccountOrdering.moving(
            [first, second, third],
            sourceID: first.id,
            targetID: third.id
        )
        XCTAssertEqual(movedForward.map(\.id), [second.id, third.id, first.id])

        let movedBackward = APIAccountOrdering.moving(
            movedForward,
            sourceID: first.id,
            targetID: second.id
        )
        XCTAssertEqual(movedBackward.map(\.id), [first.id, second.id, third.id])
    }

    func testPortalLoginIsExposedOnlyForServicesThatNeedConsoleTotals() {
        XCTAssertTrue(APIServiceID.anthropicAPI.supportsPortalConnection)
        XCTAssertTrue(APIServiceID.anthropicConsole.supportsPortalConnection)
        XCTAssertTrue(APIServiceID.deepSeek.supportsPortalConnection)
        XCTAssertTrue(APIServiceID.openAI.supportsPortalConnection)
        XCTAssertTrue(APIServiceID.openRouter.supportsPortalConnection)
        XCTAssertTrue(APIServiceID.firecrawlSubscription.supportsPortalConnection)
        XCTAssertTrue(APIServiceID.twitterAPI.supportsPortalConnection)
        XCTAssertTrue(APIServiceID.xTwitter.supportsPortalConnection)
        XCTAssertNil(APIServiceID.twitterAPI.identifierLabel)
        XCTAssertFalse(APIServiceID.elevenLabs.supportsPortalConnection)
    }

    func testClaudeSubscriptionCannotBeAddedAsAnAPIAccount() {
        XCTAssertFalse(APIServiceID.addableCases.contains(.anthropicConsole))
        XCTAssertTrue(APIServiceID.addableCases.contains(.anthropicAPI))
    }

    func testWebSubscriptionsCannotBeAddedAsAPIAccounts() {
        XCTAssertFalse(APIServiceID.addableCases.contains(.chatGPTSubscription))
        XCTAssertFalse(APIServiceID.addableCases.contains(.googleSubscription))
        XCTAssertFalse(APIServiceID.addableCases.contains(.firecrawlSubscription))
        XCTAssertTrue(APIServiceID.chatGPTSubscription.isSubscriptionService)
        XCTAssertTrue(APIServiceID.googleSubscription.isSubscriptionService)
        XCTAssertTrue(APIServiceID.firecrawlSubscription.isSubscriptionService)
    }

    func testChatGPTSubscriptionParserReadsBRLMonthlyPlan() throws {
        let quota = try XCTUnwrap(ChatGPTSubscriptionReader.parseBillingText("""
        Cobrança
        ChatGPT Pro 5x
        Seu plano será renovado automaticamente em 7 de ago. de 2026
        Novo chat
        Histórico de faturas
        7 de jul. de 2026
        R$ 525,00
        Pago
        """))

        XCTAssertEqual(quota.service, .chatGPTSubscription)
        XCTAssertEqual(quota.monthlyPlanBRL, Decimal(string: "525"))
        XCTAssertNil(quota.monthlyPlanUSD)
        XCTAssertEqual(quota.planName, "ChatGPT Pro 5x")
    }

    func testChatGPTSubscriptionParserNormalizesAnnualUSDPlan() throws {
        let quota = try XCTUnwrap(ChatGPTSubscriptionReader.parseBillingText("""
        ChatGPT Business
        US$ 300.00 per year
        Renewal date
        """))

        XCTAssertEqual(try XCTUnwrap(quota.monthlyPlanUSD), 25, accuracy: 0.001)
        XCTAssertNil(quota.monthlyPlanBRL)
    }

    func testGoogleSubscriptionParserReadsOnlyAIPlanInBRL() throws {
        let quota = try XCTUnwrap(GoogleSubscriptionReader.parseBillingText("""
        Atividade
        Google One
        23 de jul. · Google AI Plus (2 TB) (Google One)
        -R$ 49,99
        Google One
        25 de jun. · Google AI Plus (2 TB) (Google One)
        -R$ 49,99
        """))

        XCTAssertEqual(quota.service, .googleSubscription)
        XCTAssertEqual(quota.monthlyPlanBRL, Decimal(string: "49.99"))
        XCTAssertEqual(quota.planName, "Google AI Plus")
    }

    func testGoogleSubscriptionParserRejectsUnrelatedGooglePlan() {
        XCTAssertNil(GoogleSubscriptionReader.parseBillingText("""
        Assinaturas e serviços
        YouTube Premium
        R$ 24,90 / mês
        """))
    }

    func testFirecrawlSubscriptionParserReadsCurrentMonthlyPlan() throws {
        let quota = try XCTUnwrap(FirecrawlSubscriptionReader.parseBillingText("""
        Billing
        Current plan
        Standard
        $99 / month
        100,000 credits per month
        Renews on August 12, 2026
        Available plans
        Growth
        $399 / month
        """))

        XCTAssertEqual(quota.service, .firecrawlSubscription)
        XCTAssertEqual(try XCTUnwrap(quota.monthlyPlanUSD), 99, accuracy: 0.001)
        XCTAssertNil(quota.monthlyPlanBRL)
        XCTAssertEqual(quota.planName, "Standard")
        XCTAssertNotNil(quota.resetsAt)
    }

    func testFirecrawlSubscriptionParserNormalizesAnnualBRLPlan() throws {
        let quota = try XCTUnwrap(FirecrawlSubscriptionReader.parseBillingText("""
        Seu plano
        Growth
        R$ 6.096,00 / ano
        Próxima cobrança: 12 de agosto de 2026
        """))

        XCTAssertEqual(quota.monthlyPlanBRL, Decimal(string: "508"))
        XCTAssertNil(quota.monthlyPlanUSD)
        XCTAssertEqual(quota.planName, "Growth")
    }

    func testFirecrawlSubscriptionParserRejectsPricingPageWithoutCurrentPlan() {
        XCTAssertNil(FirecrawlSubscriptionReader.parseBillingText("""
        Choose a plan
        Hobby
        $19 / month
        Standard
        $99 / month
        Growth
        $399 / month
        """))
    }

    func testAnthropicCostParserConvertsOfficialCentsToUSD() throws {
        let data = try XCTUnwrap("""
        {"data":[
          {"results":[
            {"amount":"123.45","currency":"USD","cost_type":"tokens"},
            {"amount":"6.55","currency":"USD","cost_type":"web_search"}
          ]},
          {"results":[{"amount":"70","currency":"USD","cost_type":"code_execution"}]}
        ],"has_more":false,"next_page":null}
        """.data(using: .utf8))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = APIAccountSpendWindow.rolling30Days(endingAt: now)

        let quota = try XCTUnwrap(APIAccountProbe.anthropicCost(data: data, window: window))

        XCTAssertEqual(quota.service, .anthropicAPI)
        XCTAssertEqual(quota.monthlySpendUSD, 2)
        XCTAssertEqual(quota.monetaryKind, .spend)
        XCTAssertEqual(quota.spendPeriod, .rolling30Days)
        XCTAssertEqual(quota.spendWindowStart, window.start)
        XCTAssertEqual(quota.spendWindowEnd, window.end)
        XCTAssertNil(quota.balanceUSD)
    }

    #if os(macOS)
    func testAnthropicConsoleParsesCurrentMonthCostInUSD() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 12))
        )
        let quota = try XCTUnwrap(
            AnthropicAPIConsoleReader.parseCostText(
                "Cost\nJuly 2026\nTotal cost\n$23.85",
                now: now,
                calendar: calendar
            )
        )

        XCTAssertEqual(quota.service, .anthropicAPI)
        XCTAssertEqual(quota.monthlySpendUSD, 23.85)
        XCTAssertEqual(quota.spendPeriod, .currentCalendarMonth)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(quota.spendWindowStart)), 1)
        XCTAssertEqual(quota.spendWindowEnd, now)
        XCTAssertNil(quota.balanceUSD)
    }

    func testAnthropicConsoleParsesBrazilianCurrencyFormat() throws {
        let quota = try XCTUnwrap(
            AnthropicAPIConsoleReader.parseCostText(
                """
                Custo total
                Mais informações sobre o custo total
                US$ 1.234,56
                __NOTCH_CREDITS__
                Créditos
                US$ 19,94
                """
            )
        )

        XCTAssertEqual(quota.monthlySpendUSD ?? -1, 1_234.56, accuracy: 0.000_001)
        XCTAssertEqual(quota.balanceUSD ?? -1, 19.94, accuracy: 0.000_001)
        XCTAssertEqual(quota.monetaryKind, .balance)
        XCTAssertEqual(quota.spendPeriod, .currentCalendarMonth)
    }

    func testAnthropicConsoleDoesNotTreatCreditBalanceAsSpend() {
        XCTAssertNil(
            AnthropicAPIConsoleReader.parseCostText("Créditos\nUS$ 19,94")
        )
    }
    #endif

    func testLiveE2EAccountMonitoringWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NOTCHAGENT_LIVE_E2E"] == "1" else {
            throw XCTSkip("Live account monitoring runs only with NOTCHAGENT_LIVE_E2E=1")
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "br.com.lfrprojects.notchagent"))
        let data = try XCTUnwrap(defaults.data(forKey: "app.settings.v1"))
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.apiAccountMonitoringEnabled)
        let accounts = settings.apiAccounts.filter { $0.enabled && !$0.service.isSubscriptionService }
        XCTAssertEqual(accounts.count, 11)

        let snapshot = try await APIAccountProvider().fetchSnapshot(settings: settings)
        let usages = (snapshot.accountUsage ?? []).filter { !$0.service.isSubscriptionService }
        let audit = APIAccountIntegrityAuditor.audit(accounts: accounts, usages: usages)
        let reports = audit.map { item in
            let source = item.sources.map(\.rawValue).joined(separator: "+")
            let window = item.spendPeriod?.rawValue ?? "none"
            return "\(item.service.rawValue)=\(item.outcome.rawValue),source=\(source),window=\(window)"
        }.joined(separator: " | ")
        print("LIVE_API_E2E health=\(snapshot.health.rawValue) reports=\(reports)")
        XCTAssertEqual(audit.count, accounts.count)
        XCTAssertFalse(audit.contains { $0.outcome == .invalid }, reports)
    }

    func testIntegrityAuditRecordsSourceWindowAndTolerance() {
        let account = APIAccount(service: .openAI)
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = APIAccountUsage(
            accountID: account.id,
            label: account.label,
            service: account.service,
            capturedAt: end,
            usedPercent: nil,
            resetsAt: nil,
            summary: "Official",
            monthlySpendUSD: 20,
            spendPeriod: .rolling30Days,
            spendWindowStart: end.addingTimeInterval(-APIAccountSpendWindow.duration),
            spendWindowEnd: end,
            balanceUSD: 40,
            readStatus: .updated,
            origins: APIAccountFieldOrigins(spend: .officialAPI, balance: .officialPortal)
        )

        let report = APIAccountIntegrityAuditor.audit(accounts: [account], usages: [usage])

        XCTAssertEqual(report.count, 1)
        XCTAssertEqual(report[0].outcome, .verified)
        XCTAssertEqual(report[0].sources, [.officialAPI, .officialPortal])
        XCTAssertEqual(report[0].spendPeriod, .rolling30Days)
        XCTAssertEqual(report[0].tolerance.monetaryUSD, 0.02)
        XCTAssertTrue(report[0].findings.isEmpty)
    }

    func testIntegrityAuditRejectsInferredOfficialSpendAndBadFirecrawlMath() {
        let account = APIAccount(service: .firecrawl)
        let usage = APIAccountUsage(
            accountID: account.id,
            label: account.label,
            service: account.service,
            usedPercent: 100,
            resetsAt: nil,
            summary: "Invalid",
            monthlySpendUSD: 5,
            cycleUsed: 100_157,
            cycleLimit: 100_000,
            cycleRemaining: -157,
            cycleOverage: 0,
            cycleUnit: "credits",
            readStatus: .updated,
            origins: APIAccountFieldOrigins(quota: .officialAPI)
        )

        let report = APIAccountIntegrityAuditor.audit(account: account, usage: usage)

        XCTAssertEqual(report.outcome, .invalid)
        XCTAssertTrue(report.findings.contains("spend_without_source"))
        XCTAssertTrue(report.findings.contains("spend_without_exact_window"))
        XCTAssertTrue(report.findings.contains("cycle_remaining_negative"))
        XCTAssertTrue(report.findings.contains("cycle_remaining_mismatch"))
        XCTAssertTrue(report.findings.contains("cycle_overage_mismatch"))
    }

    @MainActor
    func testSanitizedDiagnosticExcludesCredentialsIdentityAmountsAndErrors() throws {
        let secret = "sk-secret-should-never-export"
        let account = APIAccount(
            service: .openAI,
            label: "Private account name",
            identifier: "private-project-id",
            keychainAccount: "private-keychain-slot",
            credentialService: .openAI
        )
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = APIAccountUsage(
            accountID: account.id,
            label: account.label,
            service: account.service,
            capturedAt: end,
            usedPercent: nil,
            resetsAt: nil,
            summary: "Request failed with \(secret)",
            monthlySpendUSD: 123.45,
            spendPeriod: .rolling30Days,
            spendWindowStart: end.addingTimeInterval(-APIAccountSpendWindow.duration),
            spendWindowEnd: end,
            readStatus: .updated,
            origins: APIAccountFieldOrigins(spend: .officialAPI)
        )
        var settings = AppSettings()
        settings.apiAccountMonitoringEnabled = true
        settings.apiAccounts = [account]
        let snapshot = UsageSnapshot(
            provider: .apiAccounts,
            capturedAt: end,
            health: .ok,
            note: "Portal response \(secret)",
            accountUsage: [usage]
        )

        let report = SanitizedDiagnosticExporter.report(
            settings: settings,
            snapshots: [.apiAccounts: snapshot],
            refreshStates: [.apiAccounts: .failure(end, "Bearer \(secret)")],
            generatedAt: end
        )
        let text = try XCTUnwrap(String(
            data: SanitizedDiagnosticExporter.data(report),
            encoding: .utf8
        ))

        XCTAssertTrue(text.contains("\"service\" : \"openai\""))
        XCTAssertTrue(text.contains("\"officialAPI\""))
        XCTAssertTrue(text.contains("\"rolling30Days\""))
        XCTAssertTrue(text.contains("\"refreshState\" : \"error\""))
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("Private account name"))
        XCTAssertFalse(text.contains("private-project-id"))
        XCTAssertFalse(text.contains("private-keychain-slot"))
        XCTAssertFalse(text.contains("123.45"))
        XCTAssertFalse(text.contains(account.id.uuidString))
    }

    func testBCBPTAXParserReadsOfficialSellingQuote() throws {
        let data = try XCTUnwrap("""
        {"value":[{"cotacaoCompra":5.066,"cotacaoVenda":5.0666,"dataHoraCotacao":"2026-07-24 13:11:23"}]}
        """.data(using: .utf8))

        XCTAssertEqual(BRLExchangeRateService.usdSaleQuote(data: data), Decimal(string: "5.0666"))
    }

    func testDisabledMonitoringNeverCreatesAQuota() async throws {
        let snapshot = try await APIAccountProvider().fetchSnapshot(settings: AppSettings())

        XCTAssertEqual(snapshot.provider, .apiAccounts)
        XCTAssertEqual(snapshot.health, .noData)
        XCTAssertNil(snapshot.session)
        XCTAssertEqual(snapshot.note, "API account monitoring is off")
    }

    func testSelectedServicesAreListedWithoutNetworkTraffic() async throws {
        var settings = AppSettings()
        settings.apiAccountMonitoringEnabled = true
        // brAPI is deliberately unsupported without an explicit metrics URL,
        // so this assertion cannot accidentally use a developer's Keychain
        // credential or issue a network request during tests.
        settings.monitoredAPIServices = [.brAPI]

        let snapshot = try await APIAccountProvider().fetchSnapshot(settings: settings)

        XCTAssertEqual(snapshot.health, .noData)
        XCTAssertTrue(snapshot.note?.contains("brapi.dev") ?? false)
        XCTAssertNil(snapshot.session)
    }

    func testSettingsPreserveSelectedServices() throws {
        var settings = AppSettings()
        settings.apiAccountMonitoringEnabled = true
        settings.apiAccounts = [
            APIAccount(service: .openRouter, label: "Equipe A"),
            APIAccount(service: .openRouter, label: "Equipe B"),
            APIAccount(service: .xTwitter, label: "Agente X 1"),
        ]

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertTrue(decoded.apiAccountMonitoringEnabled)
        XCTAssertEqual(decoded.apiAccounts.map(\.label), ["Equipe A", "Equipe B", "Agente X 1"])
        XCTAssertEqual(decoded.apiAccounts.map(\.service), [.openRouter, .openRouter, .xTwitter])
    }

    func testCredentialIsNeverReusedForAnotherService() {
        let account = APIAccount(
            service: .openAI,
            credentialService: .openRouter,
            credentialRevision: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertFalse(APIAccountCredentialStore.credentialIsCompatible(with: account))

        var legacyAccount = account
        legacyAccount.credentialService = nil
        XCTAssertTrue(APIAccountCredentialStore.credentialIsCompatible(with: legacyAccount))
    }

    func testLegacySettingsMigrateEachServiceToAnAccount() throws {
        let data = try XCTUnwrap("""
        {"monitoredAPIServices":["openrouter","x-twitter-account-1"],"apiAccountMonitoringEnabled":true}
        """.data(using: .utf8))

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.apiAccounts.count, 2)
        XCTAssertTrue(settings.apiAccounts.contains { $0.service == .openRouter })
        XCTAssertTrue(settings.apiAccounts.contains { $0.service == .xTwitter })
    }

    func testFirecrawlSubscriptionMigrationCopiesFallbackOnce() {
        var settings = AppSettings()
        settings.apiAccounts = [
            APIAccount(service: .firecrawl, monthlyPlanBRL: Decimal(string: "508")),
        ]
        settings.webSubscriptionAccountsInitialized = true

        settings.ensureWebSubscriptionAccountsIfNeeded()
        settings.ensureWebSubscriptionAccountsIfNeeded()

        let subscriptions = settings.apiAccounts.filter { $0.service == .firecrawlSubscription }
        XCTAssertEqual(subscriptions.count, 1)
        XCTAssertEqual(subscriptions.first?.monthlyPlanBRL, Decimal(string: "508"))
        XCTAssertTrue(settings.firecrawlSubscriptionAccountInitialized)
    }

    func testAccountUsageSurvivesSnapshotPersistence() throws {
        let account = APIAccountUsage(
            accountID: UUID(),
            label: "ElevenLabs production",
            service: .elevenLabs,
            usedPercent: 42,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
            summary: "ElevenLabs production: 5,800 credits remaining",
            billingScopeID: "vendor-project:123"
        )
        let snapshot = UsageSnapshot(provider: .apiAccounts, health: .ok, accountUsage: [account])

        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(decoded.accountUsage, [account])
    }

    func testOpenRouterParserUsesKeyLimitWithoutReadingRequests() throws {
        let data = try XCTUnwrap("""
        {"data":{"usage":25.5,"usage_monthly":5.25,"limit":100,"limit_remaining":74.5,"limit_reset":"monthly"}}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.openRouterQuota(data: data))

        XCTAssertEqual(quota.service, .openRouter)
        XCTAssertEqual(quota.usedPercent, 25.5)
        XCTAssertEqual(quota.note, "OpenRouter key spend this month: 5.25 USD · key limit remaining: 74.50 USD, resets monthly")
        XCTAssertNil(quota.monetaryUSD)
        XCTAssertNil(quota.monetaryKind)
        XCTAssertNil(quota.monthlySpendUSD)
        XCTAssertNil(quota.balanceUSD)
        XCTAssertEqual(quota.cycleUsed, 25.5)
        XCTAssertEqual(quota.cycleLimit, 100)
        XCTAssertEqual(quota.cycleUnit, "USD")
    }

    func testOpenRouterZeroKeyLimitIsNotAccountBalance() throws {
        let data = try XCTUnwrap("""
        {"data":{"usage":0,"usage_monthly":0,"limit":0,"limit_remaining":0,"limit_reset":null}}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.openRouterQuota(data: data))

        XCTAssertEqual(quota.note, "OpenRouter key spend this month: 0.00 USD")
        XCTAssertNil(quota.monthlySpendUSD)
        XCTAssertNil(quota.balanceUSD)
        XCTAssertNil(quota.cycleLimit)
    }

    func testOpenRouterCreditsParserAndMergeUseAccountBalance() throws {
        let creditsData = try XCTUnwrap("""
        {"data":{"total_credits":110,"total_usage":40.748988223}}
        """.data(using: .utf8))
        let credits = try XCTUnwrap(APIAccountProbe.openRouterCreditsQuota(data: creditsData))
        let key = AccountQuota(
            service: .openRouter,
            usedPercent: nil,
            resetsAt: nil,
            note: "OpenRouter key spend this month: 0.00 USD"
        )

        let quota = try XCTUnwrap(APIAccountProbe.mergeOpenRouter(key: key, credits: credits))

        XCTAssertNil(quota.monthlySpendUSD)
        XCTAssertEqual(quota.balanceUSD ?? -1, 69.251011777, accuracy: 0.000_000_001)
        XCTAssertEqual(quota.monetaryKind, .balance)
        XCTAssertEqual(quota.note, "OpenRouter key spend this month: 0.00 USD · OpenRouter account balance: 69.25 USD")
    }

    func testOpenRouterPortalParserReadsLocalizedPastMonthSpend() throws {
        let text = """
        Activity
        Past 1 Month
        Total spend
        $439,92
        Requests
        15K
        """

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = try XCTUnwrap(OpenRouterConsoleReader.parseActivityText(text, now: now))

        XCTAssertEqual(quota.monthlySpendUSD, 439.92)
        XCTAssertEqual(quota.note, "OpenRouter Portal: last 30 days 439.92 USD")
        XCTAssertEqual(quota.spendPeriod, .rolling30Days)
        XCTAssertEqual(quota.spendWindowStart, now.addingTimeInterval(-APIAccountSpendWindow.duration))
        XCTAssertEqual(quota.spendWindowEnd, now)
    }

    func testOpenRouterAccountMergeUsesPortalSpendAndAPIBalance() throws {
        let api = AccountQuota(
            service: .openRouter,
            usedPercent: nil,
            resetsAt: nil,
            note: "API balance",
            balanceUSD: 69.251011777
        )
        let portal = AccountQuota(
            service: .openRouter,
            usedPercent: nil,
            resetsAt: nil,
            note: "Portal spend",
            monthlySpendUSD: 439.92
        )

        let quota = try XCTUnwrap(APIAccountProbe.mergeOpenRouterAccount(api: api, portal: portal))

        XCTAssertEqual(quota.monthlySpendUSD, 439.92)
        XCTAssertEqual(quota.balanceUSD ?? -1, 69.251011777, accuracy: 0.000_000_001)
        XCTAssertEqual(quota.monetaryKind, .balance)
    }

    func testElevenLabsQuotaParserUsesOnlyQuotaFields() throws {
        let data = try XCTUnwrap("""
        {"character_count":2500,"character_limit":10000,"next_character_count_reset_unix":1800000000,"currency":"usd","current_overage":{"amount":"1.25","currency":"usd"},"next_invoice":{"amount_due_cents":2200},"user_id":"ignored"}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.elevenLabsQuota(data: data))

        XCTAssertEqual(quota.service, .elevenLabs)
        XCTAssertEqual(quota.usedPercent, 25)
        XCTAssertEqual(quota.resetsAt?.timeIntervalSince1970, 1_800_000_000)
        XCTAssertEqual(quota.cycleUsed, 2_500)
        XCTAssertEqual(quota.cycleLimit, 10_000)
        XCTAssertEqual(quota.cycleUnit, "créditos")
        XCTAssertEqual(quota.monthlySpendUSD, 1.25)
        XCTAssertEqual(quota.monthlyPlanUSD, 22)
    }

    func testFirecrawlQuotaParserCalculatesUsedPercent() throws {
        let data = try XCTUnwrap("""
        {"success":true,"data":{"remainingCredits":750,"planCredits":1000,"billingPeriodEnd":"2026-08-01T00:00:00Z"}}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.firecrawlQuota(data: data))

        XCTAssertEqual(quota.usedPercent, 25)
        XCTAssertEqual(quota.service, .firecrawl)
        XCTAssertEqual(quota.cycleUsed, 250)
        XCTAssertEqual(quota.cycleLimit, 1_000)
        XCTAssertEqual(quota.cycleRemaining, 750)
        XCTAssertEqual(quota.cycleOverage, 0)
        XCTAssertEqual(quota.cycleUnit, "créditos")
        XCTAssertEqual(quota.origins.quota, .officialAPI)
    }

    func testFirecrawlNegativeRemainingBecomesZeroPlusOverage() throws {
        let data = try XCTUnwrap("""
        {"success":true,"data":{"remainingCredits":-157,"planCredits":100000,"billingPeriodEnd":"2026-08-01T00:00:00Z"}}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.firecrawlQuota(data: data))

        XCTAssertEqual(quota.usedPercent, 100)
        XCTAssertEqual(quota.cycleUsed, 100_157)
        XCTAssertEqual(quota.cycleLimit, 100_000)
        XCTAssertEqual(quota.cycleRemaining, 0)
        XCTAssertEqual(quota.cycleOverage, 157)
        XCTAssertFalse(quota.note.contains("-157"))
    }

    func testDeepSeekParserReportsBalanceWithoutInventingAPercent() throws {
        let data = try XCTUnwrap("""
        {"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"12.50"}]}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.deepSeekBalance(data: data))

        XCTAssertNil(quota.usedPercent)
        XCTAssertEqual(quota.note, "DeepSeek balance: 12.50 USD")
        XCTAssertEqual(quota.monetaryUSD, 12.5)
        XCTAssertEqual(quota.monetaryKind, .balance)
        XCTAssertNil(quota.monthlySpendUSD)
        XCTAssertEqual(quota.balanceUSD, 12.5)
    }

    func testDeepSeekConsoleParserReadsRenderedSpendAndBalance() throws {
        let text = """
        Usage
        Topped-up balance
        Balance alert enabled
        $36.51 USD
        Total cost
        $38.48 USD
        Time
        Last 30 days
        Cost
        $6.07 USD
        """

        let quota = try XCTUnwrap(DeepSeekConsoleReader.parseUsageText(text))

        XCTAssertEqual(quota.monthlySpendUSD, 6.07)
        XCTAssertEqual(quota.balanceUSD, 36.51)
    }

    func testDeepSeekConsoleParserReadsResponsiveFlattenedCards() throws {
        let text = """
        Usage
        Topped-up balance Balance alert enabled Settings $36.37 USD Top up
        Total cost $38.62 USD
        Time Last 30 days API Key All Export
        Cost $6.21 USD API requests 32,124 Tokens 188,117,461
        Cost(USD) $6.21
        """

        let quota = try XCTUnwrap(DeepSeekConsoleReader.parseUsageText(text))

        XCTAssertEqual(quota.monthlySpendUSD, 6.21)
        XCTAssertEqual(quota.balanceUSD, 36.37)
        XCTAssertNotEqual(quota.monthlySpendUSD, 38.62)
    }

    func testDeepSeekMergePrefersConsoleSpendAndAPIBalance() throws {
        let api = AccountQuota(service: .deepSeek, usedPercent: nil, resetsAt: nil, note: "API balance", balanceUSD: 36.51)
        let console = AccountQuota(service: .deepSeek, usedPercent: nil, resetsAt: nil, note: "Console spend", monthlySpendUSD: 6.07, balanceUSD: 36.40)

        let quota = try XCTUnwrap(APIAccountProbe.mergeDeepSeek(api: api, console: console))

        XCTAssertEqual(quota.monthlySpendUSD, 6.07)
        XCTAssertEqual(quota.balanceUSD, 36.51)
    }

    func testClaudeTeamBillingParserReadsOfficialBRLPlanAndCredits() throws {
        let text = """
        Seu plano
        Plano atual plano Equipe Licenças
        Quantidade de licenças
        10 (0 disponíveis)
        Próxima fatura
        Data de renovação da assinatura
        23 de ago. de 2026
        Total projetado
        R$ 1.848,40
        Créditos de uso
        -R$ 0,10
        Saldo atual
        """

        let quota = try XCTUnwrap(AnthropicConsoleReader.parseBillingText(text))

        XCTAssertEqual(quota.monthlyPlanBRL, Decimal(string: "1848.40"))
        XCTAssertEqual(quota.balanceBRL, Decimal(string: "-0.10"))
        XCTAssertEqual(quota.planName, "Equipe")
        XCTAssertEqual(quota.seatCount, 10)
        XCTAssertEqual(
            quota.note,
            "Claude: plano Equipe · próxima fatura R$ 1.848,40 · 10 licenças · créditos de uso -R$ 0,10"
        )
    }

    func testClaudeBillingParserDoesNotUseInvoiceHistoryAsNextInvoice() {
        let text = """
        Faturas
        23 de jul. de 2026
        R$ 1.848,40
        Paid
        """

        XCTAssertNil(AnthropicConsoleReader.parseBillingText(text))
    }

    func testOpenAICostParserSumsAllBuckets() throws {
        let data = try XCTUnwrap("""
        {"data":[
          {"results":[{"amount":{"value":0.06,"currency":"usd"}}]},
          {"results":[{"amount":{"value":1.24,"currency":"usd"}}]}
        ]}
        """.data(using: .utf8))

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = APIAccountSpendWindow.rolling30Days(endingAt: now)
        let quota = try XCTUnwrap(APIAccountProbe.openAICost(data: data, window: window))

        XCTAssertNil(quota.usedPercent)
        XCTAssertEqual(quota.note, "OpenAI spend last 30 days: 1.30 USD")
        XCTAssertEqual(quota.monetaryUSD, 1.3)
        XCTAssertEqual(quota.monetaryKind, .spend)
        XCTAssertEqual(quota.monthlySpendUSD, 1.3)
        XCTAssertEqual(quota.spendPeriod, .rolling30Days)
        XCTAssertEqual(quota.spendWindowStart, window.start)
        XCTAssertEqual(quota.spendWindowEnd, window.end)
        XCTAssertNil(quota.balanceUSD)
    }

    func testOpenAICostParserAcceptsOfficialDecimalStrings() throws {
        let data = try XCTUnwrap("""
        {"data":[{"results":[{"amount":{"value":"23.85","currency":"usd"}}]}]}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.openAICost(data: data))

        XCTAssertEqual(quota.monthlySpendUSD, 23.85)
    }

    func testOpenAIPortalParserReadsPrepaidBalance() throws {
        let text = """
        Billing overview
        Credit balance
        $42.75
        Add to balance
        """

        let quota = try XCTUnwrap(OpenAIConsoleReader.parseBillingText(text))

        XCTAssertEqual(quota.balanceUSD, 42.75)
        XCTAssertNil(quota.monthlySpendUSD)
    }

    func testOpenAIPortalParserReadsPortugueseCurrencyFormat() throws {
        let quota = try XCTUnwrap(OpenAIConsoleReader.parseBillingText("Saldo pré-pago US$ 1.234,56"))

        XCTAssertEqual(quota.balanceUSD, 1_234.56)
    }

    func testOpenAIMergeKeepsOfficialSpendAndPortalBalanceSeparate() throws {
        let api = AccountQuota(service: .openAI, usedPercent: nil, resetsAt: nil, note: "API", monthlySpendUSD: 27.88)
        let portal = AccountQuota(service: .openAI, usedPercent: nil, resetsAt: nil, note: "Portal", balanceUSD: 42.75)

        let quota = try XCTUnwrap(APIAccountProbe.mergeOpenAI(api: api, portal: portal))

        XCTAssertEqual(quota.monthlySpendUSD, 27.88)
        XCTAssertEqual(quota.balanceUSD, 42.75)
        XCTAssertEqual(quota.monetaryKind, .balance)
    }

    func testOpenAIBalanceStabilizerRejectsCachedFirstRender() {
        var stabilizer = OpenAIBalanceStabilizer(minimumAttempt: 2)

        XCTAssertFalse(stabilizer.accepts(500, attempt: 0))
        XCTAssertFalse(stabilizer.accepts(202.40, attempt: 1))
        XCTAssertTrue(stabilizer.accepts(202.40, attempt: 2))
    }

    func testHeyGenUsageBasedParserUsesOfficialSpendingCap() throws {
        let data = try XCTUnwrap("""
        {"data":{"billing_type":"usage_based","usage_based":{"spending_current_usd":15,"spending_cap_usd":60}}}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.heyGenQuota(data: data))

        XCTAssertEqual(quota.usedPercent, 25)
        XCTAssertEqual(quota.note, "HeyGen spend: 15.00 USD / 60.00 USD")
        XCTAssertEqual(quota.monetaryUSD, 15)
        XCTAssertEqual(quota.monetaryKind, .spend)
        XCTAssertEqual(quota.monthlySpendUSD, 15)
    }

    func testTwilioUsageParserUsesTotalPriceOnly() throws {
        let data = try XCTUnwrap("""
        {"usage_records":[
          {"category":"calls","price":2.50,"price_unit":"usd"},
          {"category":"totalprice","price":"4.75","price_unit":"usd"}
        ]}
        """.data(using: .utf8))

        let window = APIAccountSpendWindow.rolling30Days(endingAt: Date(timeIntervalSince1970: 1_800_000_000))
        let quota = try XCTUnwrap(APIAccountProbe.twilioSpend(data: data, window: window))

        XCTAssertNil(quota.usedPercent)
        XCTAssertEqual(quota.note, "Twilio spend last 30 days: 4.75 USD")
        XCTAssertEqual(quota.monetaryUSD, 4.75)
        XCTAssertEqual(quota.monetaryKind, .spend)
        XCTAssertEqual(quota.spendPeriod, .rolling30Days)
    }

    func testXAIBalanceConvertsSignedCentsToAvailableUSD() throws {
        let data = try XCTUnwrap("""
        {"changes":[],"total":{"val":"-1000"}}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.xAIPrepaidBalance(data: data))

        XCTAssertNil(quota.usedPercent)
        XCTAssertEqual(quota.note, "xAI prepaid balance: 10.00 USD")
        XCTAssertEqual(quota.balanceUSD, 10)
    }

    func testXAIUsageSumsOfficialMonthlySeries() throws {
        let balance = try XCTUnwrap("{\"changes\":[],\"total\":{\"val\":\"-1000\"}}".data(using: .utf8))
        let usage = try XCTUnwrap("{\"timeSeries\":[{\"dataPoints\":[{\"values\":[1.25]},{\"values\":[0.75]}]}]}".data(using: .utf8))

        let window = APIAccountSpendWindow.rolling30Days(endingAt: Date(timeIntervalSince1970: 1_800_000_000))
        let quota = try XCTUnwrap(APIAccountProbe.xAIPrepaidBalance(data: balance, usageData: usage, window: window))

        XCTAssertEqual(quota.monthlySpendUSD, 2)
        XCTAssertEqual(quota.balanceUSD, 10)
        XCTAssertEqual(quota.note, "xAI spend last 30 days: 2.00 USD · prepaid balance: 10.00 USD")
        XCTAssertEqual(quota.spendPeriod, .rolling30Days)
    }

    func testXAIEmptyOfficialUsageSeriesMeansZeroSpend() throws {
        let balance = try XCTUnwrap("{\"changes\":[],\"total\":{\"val\":\"-1000\"}}".data(using: .utf8))
        let usage = try XCTUnwrap("{\"timeSeries\":[]}".data(using: .utf8))

        let window = APIAccountSpendWindow.rolling30Days(endingAt: Date(timeIntervalSince1970: 1_800_000_000))
        let quota = try XCTUnwrap(APIAccountProbe.xAIPrepaidBalance(data: balance, usageData: usage, window: window))

        XCTAssertEqual(quota.monthlySpendUSD, 0)
        XCTAssertEqual(quota.balanceUSD, 10)
        XCTAssertEqual(quota.note, "xAI spend last 30 days: 0.00 USD · prepaid balance: 10.00 USD")
        XCTAssertEqual(quota.spendPeriod, .rolling30Days)
    }

    func testXAIExhaustedPrepaidBalanceNeverBecomesNegative() throws {
        let data = try XCTUnwrap("""
        {"changes":[],"total":{"val":"250"}}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.xAIPrepaidBalance(data: data))

        XCTAssertEqual(quota.balanceUSD, 0)
    }

    func testXUsageParserReadsProjectCapAndMonthlyConsumption() throws {
        let data = try XCTUnwrap("""
        {"data":{"project_id":"project-123","project_usage":2500,"project_cap":10000}}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.xTwitterUsage(data: data))

        XCTAssertEqual(quota.usedPercent, 25)
        XCTAssertEqual(quota.cycleUsed, 2_500)
        XCTAssertEqual(quota.cycleLimit, 10_000)
        XCTAssertEqual(quota.cycleUnit, "posts")
        XCTAssertEqual(quota.billingScopeID, "x-project:project-123")
        XCTAssertNil(quota.monthlySpendUSD)
        XCTAssertNil(quota.balanceUSD)
    }

    func testXMergeKeepsQuotaAndAddsPortalFinancials() {
        let api = AccountQuota(
            service: .xTwitter,
            usedPercent: 25,
            resetsAt: nil,
            note: "X API quota",
            cycleUsed: 2_500,
            cycleLimit: 10_000,
            cycleUnit: "posts",
            billingScopeID: "x-project:project-123"
        )
        let portal = AccountQuota(
            service: .xTwitter,
            usedPercent: nil,
            resetsAt: nil,
            note: "X console",
            monthlySpendUSD: 12.5,
            balanceUSD: 40,
            billingScopeID: "x-console:/accounts/billing-456"
        )

        let quota = APIAccountProbe.mergeXTwitter(api: api, portal: portal)

        XCTAssertEqual(quota?.monthlySpendUSD, 12.5)
        XCTAssertEqual(quota?.balanceUSD, 40)
        XCTAssertEqual(quota?.cycleUsed, 2_500)
        XCTAssertEqual(quota?.billingScopeID, "x-console:/accounts/billing-456")
    }

    func testXConsoleParsersReadCycleSpendAndBalance() throws {
        let dashboard = """
        Credit remaining
        $69.25
        Total Balance
        """
        let usage = """
        Billing Cycle Usage
        Total Cost
        $439.92
        Total Requests
        15K
        """

        let balance = try XCTUnwrap(XDeveloperConsoleReader.parseDashboardText(dashboard))
        let spend = try XCTUnwrap(XDeveloperConsoleReader.parseUsageText(usage))

        XCTAssertEqual(balance.balanceUSD, 69.25)
        XCTAssertEqual(spend.monthlySpendUSD, 439.92)
    }

    func testXConsoleParserAcceptsBrazilianNumberFormatting() throws {
        let dashboard = """
        Saldo Total
        US$ 1.234,56
        """

        let quota = try XCTUnwrap(XDeveloperConsoleReader.parseDashboardText(dashboard))

        XCTAssertEqual(quota.balanceUSD, 1_234.56)
    }

    func testXConsoleFindsAccountRouteAfterClientSideNavigation() throws {
        let route = XDeveloperConsoleReader.accountRoute(
            from: try XCTUnwrap(URL(string: "https://console.x.com/accounts/123456/usage"))
        )

        XCTAssertEqual(route, "/accounts/123456")
        XCTAssertNil(XDeveloperConsoleReader.accountRoute(from: URL(string: "https://console.x.com/")))
    }

    func testTwitterAPIIOParserConvertsPublishedCreditBalanceToUSD() throws {
        let data = try XCTUnwrap("""
        {"recharge_credits":250000}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.twitterAPIIOBalance(data: data))

        XCTAssertEqual(quota.cycleUsed, 250_000)
        XCTAssertEqual(quota.cycleUnit, "créditos restantes")
        XCTAssertEqual(quota.balanceUSD, 2.5)
        XCTAssertEqual(quota.monetaryKind, .balance)
        XCTAssertEqual(quota.note, "twitterapi.io: 250000 credits remaining · 2.50 USD equivalent")
        XCTAssertNil(quota.origins.quota)
    }

    func testTwitterAPIIOPortalParserReadsThirtyDaySpendAndBalance() throws {
        let data = try XCTUnwrap("""
        {
          "consumption": {
            "status": "success",
            "data": {
              "window_30d": {
                "calls": 42,
                "credits_consumed": 390000
              }
            }
          },
          "billing": {
            "status": "success",
            "data": {
              "current_balance_cents": 2346
            }
          }
        }
        """.data(using: .utf8))

        let quota = try XCTUnwrap(TwitterAPIIOConsoleReader.parsePortalPayload(data))

        XCTAssertEqual(quota.monthlySpendUSD, 3.9)
        XCTAssertEqual(quota.balanceUSD, 23.46)
        XCTAssertEqual(quota.cycleUsed, 390_000)
        XCTAssertEqual(quota.cycleUnit, "créditos consumidos em 30 dias")
        XCTAssertEqual(quota.monetaryKind, .balance)
    }

    func testTwitterAPIIOAccountMergeKeepsAPIBalanceAndPortalSpend() throws {
        let api = AccountQuota(
            service: .twitterAPI,
            usedPercent: nil,
            resetsAt: nil,
            note: "API balance",
            balanceUSD: 23.45
        )
        let portal = AccountQuota(
            service: .twitterAPI,
            usedPercent: nil,
            resetsAt: nil,
            note: "Portal spend",
            monthlySpendUSD: 3.9,
            balanceUSD: 23.46,
            cycleUsed: 390_000,
            cycleUnit: "créditos consumidos em 30 dias"
        )

        let quota = try XCTUnwrap(APIAccountProbe.mergeTwitterAPIIO(api: api, portal: portal))

        XCTAssertEqual(quota.monthlySpendUSD, 3.9)
        XCTAssertEqual(quota.balanceUSD, 23.45)
        XCTAssertEqual(quota.cycleUsed, 390_000)
        XCTAssertEqual(quota.monetaryKind, .balance)
    }

    func testUnifiedSpendRejectsValuesWithoutRollingThirtyDayBounds() {
        let accountID = UUID()
        let unbounded = APIAccountUsage(
            accountID: accountID,
            label: "Unknown period",
            service: .heyGen,
            usedPercent: nil,
            resetsAt: nil,
            summary: "Vendor did not identify its period",
            monthlySpendUSD: 999
        )
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let bounded = APIAccountUsage(
            accountID: accountID,
            label: "Comparable",
            service: .openAI,
            usedPercent: nil,
            resetsAt: nil,
            summary: "Official 30-day spend",
            monthlySpendUSD: 23.85,
            spendPeriod: .rolling30Days,
            spendWindowStart: end.addingTimeInterval(-APIAccountSpendWindow.duration),
            spendWindowEnd: end
        )

        XCTAssertNil(unbounded.rolling30DaySpendUSD)
        XCTAssertEqual(bounded.rolling30DaySpendUSD, 23.85)
    }

    func testStandardQuotaAcceptsRemainingPercentForInternalMetrics() throws {
        let data = try XCTUnwrap("""
        {"remaining_percent":35,"resets_at":"2026-08-01T00:00:00Z","note":"swen queue budget"}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.standardQuota(data: data, service: .swen))

        XCTAssertEqual(quota.usedPercent, 65)
        XCTAssertEqual(quota.note, "swen queue budget")
        XCTAssertNotNil(quota.resetsAt)
    }

    func testGoogleCloudQuotaPairsUsageWithOfficialLimit() throws {
        let usage = try XCTUnwrap("""
        {"timeSeries":[{"metric":{"labels":{"quota_metric":"generativelanguage.googleapis.com/generate_content_requests"}},"resource":{"labels":{"service":"generativelanguage.googleapis.com","location":"global"}},"points":[{"value":{"int64Value":"70"}}]}]}
        """.data(using: .utf8))
        let limit = try XCTUnwrap("""
        {"timeSeries":[{"metric":{"labels":{"quota_metric":"generativelanguage.googleapis.com/generate_content_requests"}},"resource":{"labels":{"service":"generativelanguage.googleapis.com","location":"global"}},"points":[{"value":{"int64Value":"100"}}]}]}
        """.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.googleCloudQuota(usageData: usage, limitData: limit))

        XCTAssertEqual(quota.usedPercent, 70)
        XCTAssertTrue(quota.note.contains("70% used"))
    }

    func testGoogleCloudEmptySeriesMeansConnectedWithoutInventingUsage() throws {
        let empty = try XCTUnwrap(#"{"timeSeries":[]}"#.data(using: .utf8))

        let quota = try XCTUnwrap(APIAccountProbe.googleCloudQuota(usageData: empty, limitData: empty))

        XCTAssertNil(quota.usedPercent)
        XCTAssertTrue(quota.note.contains("connected"))
        XCTAssertTrue(quota.note.contains("no allocation quota activity"))
    }

    func testGoogleAIStudioParserReadsTwentyEightDayBRLSpend() throws {
        let text = """
        Gasto da API Gemini
        Seu custo total
        June 28 - July 27, 2026
        Custo
        R$699,64
        Economia
        R$0,00
        Custo total
        R$699,64
        28 dias
        """

        let quota = try XCTUnwrap(GoogleAIStudioConsoleReader.parseSpendText(
            text,
            projectID: "sample-project-123456",
            brlPerUSD: 5.0
        ))

        XCTAssertEqual(quota.monthlySpendUSD ?? -1, 139.928, accuracy: 0.000_001)
        XCTAssertEqual(quota.monthlySpendBRL, Decimal(string: "699.64"))
        XCTAssertEqual(quota.spendPeriod, .rolling28Days)
        XCTAssertEqual(quota.billingScopeID, "google-project:sample-project-123456")
    }

    func testGoogleNativeBRLSpendDoesNotDriftAfterExchangeRateChanges() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = try XCTUnwrap(GoogleAIStudioConsoleReader.parseSpendText(
            "Seu custo total Custo total R$699,64 28 dias",
            projectID: "project",
            brlPerUSD: 5,
            now: now
        ))
        let account = APIAccount(service: .gemini)
        let usage = APIAccountUsage(
            accountID: account.id,
            label: account.label,
            service: account.service,
            usedPercent: nil,
            resetsAt: nil,
            summary: quota.note,
            monthlySpendUSD: quota.monthlySpendUSD,
            monthlySpendBRL: quota.monthlySpendBRL,
            spendPeriod: quota.spendPeriod,
            spendWindowStart: quota.spendWindowStart,
            spendWindowEnd: quota.spendWindowEnd,
            readStatus: .updated,
            origins: APIAccountFieldOrigins(spend: .officialPortal)
        )

        let finance = APIAccountFinancePresentation(
            account: account,
            usage: usage,
            brlPerUSD: 6
        )

        XCTAssertEqual(finance.spend.amountBRL, Decimal(string: "699.64"))
        XCTAssertEqual(finance.spend.confidence, .officialPortal)
    }

    func testGoogleAIStudioParserRejectsNinetyDayWindow() {
        let text = "Seu custo total Custo total R$1.84K 90 dias"

        XCTAssertNil(GoogleAIStudioConsoleReader.parseSpendText(
            text,
            projectID: "project",
            brlPerUSD: 5.0
        ))
    }

    func testGoogleMergeKeepsQuotaAndAddsPortalSpend() throws {
        let api = AccountQuota(service: .gemini, usedPercent: 20, resetsAt: nil, note: "quota")
        let portal = AccountQuota(
            service: .gemini,
            usedPercent: nil,
            resetsAt: nil,
            note: "spend",
            monthlySpendUSD: 100,
            spendPeriod: .rolling30Days,
            spendWindowStart: Date(timeIntervalSince1970: 1),
            spendWindowEnd: Date(timeIntervalSince1970: 2),
            billingScopeID: "google-project:test"
        )

        let merged = try XCTUnwrap(APIAccountProbe.mergeGoogleCloud(api: api, portal: portal))

        XCTAssertEqual(merged.usedPercent, 20)
        XCTAssertEqual(merged.monthlySpendUSD, 100)
        XCTAssertEqual(merged.billingScopeID, "google-project:test")
    }
}
