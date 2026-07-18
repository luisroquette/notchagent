import XCTest
@testable import AgentMeterCore

final class SubscriptionTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testMonthlyTotalsIncludeTaxes() {
        let subscription = AISubscription(
            provider: .claude,
            planName: "Pro",
            basePriceBRL: 100,
            taxPercentage: 10,
            billingCycle: .monthly,
            nextRenewalDate: .distantFuture
        )

        XCTAssertEqual(subscription.cycleTotalBRL, 110)
        XCTAssertEqual(subscription.monthlyEquivalentBRL, 110)
        XCTAssertEqual(subscription.projectedAnnualBRL, 1_320)
    }

    func testYearlyPlanIsNormalizedForMonthlySummary() {
        let subscription = AISubscription(
            provider: .gemini,
            planName: "Advanced",
            basePriceBRL: 1_200,
            billingCycle: .yearly,
            nextRenewalDate: .distantFuture
        )

        XCTAssertEqual(subscription.monthlyEquivalentBRL, 100)
        XCTAssertEqual(subscription.projectedAnnualBRL, 1_200)
    }

    func testRenewalAttentionUsesConfiguredWindow() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let renewal = calendar.date(byAdding: .day, value: 3, to: today)!
        let subscription = AISubscription(
            provider: .chatGPT,
            planName: "Plus",
            basePriceBRL: 99,
            nextRenewalDate: renewal,
            reminderDaysBefore: 3
        )

        XCTAssertTrue(subscription.needsRenewalAttention(referenceDate: today, calendar: calendar))
    }

    func testRenewalConfirmationPreservesMonthlyCadenceWhenConfirmedEarly() {
        let due = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let confirmed = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let subscription = AISubscription(
            provider: .claude,
            planName: "Pro",
            basePriceBRL: 99,
            billingCycle: .monthly,
            nextRenewalDate: due
        )

        let next = subscription.nextRenewal(after: confirmed, calendar: calendar)

        XCTAssertEqual(next, calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
    }

    func testRenewalConfirmationCatchesUpOverdueYearlySubscription() {
        let due = calendar.date(from: DateComponents(year: 2024, month: 7, day: 1))!
        let confirmed = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        let subscription = AISubscription(
            provider: .gemini,
            planName: "Advanced",
            basePriceBRL: 1_000,
            billingCycle: .yearly,
            nextRenewalDate: due
        )

        let next = subscription.nextRenewal(after: confirmed, calendar: calendar)

        XCTAssertEqual(next, calendar.date(from: DateComponents(year: 2027, month: 7, day: 1)))
    }

    func testSyncMergeKeepsNewestVersion() {
        let id = UUID()
        let old = AISubscription(
            id: id,
            provider: .claude,
            planName: "Old",
            basePriceBRL: 100,
            nextRenewalDate: .distantFuture,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let new = AISubscription(
            id: id,
            provider: .claude,
            planName: "New",
            basePriceBRL: 120,
            nextRenewalDate: .distantFuture,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let merged = SubscriptionSyncSnapshot(subscriptions: [old])
            .merged(with: SubscriptionSyncSnapshot(subscriptions: [new]))

        XCTAssertEqual(merged.subscriptions, [new])
    }

    func testSyncMergeHonorsNewerDeletion() {
        let subscription = AISubscription(
            provider: .gemini,
            planName: "Advanced",
            basePriceBRL: 100,
            nextRenewalDate: .distantFuture,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let deletion = Date(timeIntervalSince1970: 200)

        let merged = SubscriptionSyncSnapshot(subscriptions: [subscription])
            .merged(with: SubscriptionSyncSnapshot(subscriptions: [], tombstones: [subscription.id: deletion]))

        XCTAssertTrue(merged.subscriptions.isEmpty)
        XCTAssertEqual(merged.tombstones[subscription.id], deletion)
    }

    func testSyncMergePreservesDistinctHistoryEvents() {
        let first = SubscriptionHistoryEvent(
            subscriptionID: UUID(), provider: .claude, planName: "Pro", kind: .renewalConfirmed, amountBRL: 99
        )
        let second = SubscriptionHistoryEvent(
            subscriptionID: UUID(), provider: .gemini, planName: "Advanced", kind: .priceChanged, amountBRL: 100
        )

        let merged = SubscriptionSyncSnapshot(subscriptions: [], history: [first])
            .merged(with: SubscriptionSyncSnapshot(subscriptions: [], history: [first, second]))

        XCTAssertEqual(Set(merged.history.map(\.id)), Set([first.id, second.id]))
    }

    @MainActor
    func testStorePersistsSubscriptions() {
        let suite = "SubscriptionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "subscriptions"
        let original = AISubscription(
            provider: .claude,
            planName: "Pro",
            basePriceBRL: 120,
            nextRenewalDate: .distantFuture
        )

        SubscriptionStore(defaults: defaults, storageKey: key).add(original)
        let restored = SubscriptionStore(defaults: defaults, storageKey: key)

        XCTAssertEqual(restored.subscriptions, [original])
    }

    @MainActor
    func testStoreConfirmationAdvancesAndKeepsSubscription() {
        let suite = "SubscriptionRenewalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let due = calendar.date(byAdding: .day, value: 2, to: Date())!
        let subscription = AISubscription(
            provider: .chatGPT,
            planName: "Plus",
            basePriceBRL: 99,
            nextRenewalDate: due
        )
        let store = SubscriptionStore(defaults: defaults, storageKey: "subscriptions")
        store.add(subscription)

        let renewed = store.confirmRenewal(id: subscription.id, on: Date())

        XCTAssertEqual(store.subscriptions.count, 1)
        XCTAssertEqual(renewed?.nextRenewalDate, Calendar.current.date(byAdding: .month, value: 1, to: due))
    }

    @MainActor
    func testHistoryRecordsRenewalPriceChangeAndCancellation() {
        let suite = "SubscriptionHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let subscription = AISubscription(
            provider: .claude,
            planName: "Pro",
            basePriceBRL: 100,
            nextRenewalDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        )
        let store = SubscriptionStore(defaults: defaults, storageKey: "subscriptions")
        store.add(subscription)
        _ = store.confirmRenewal(id: subscription.id)

        var changed = subscription
        changed.basePriceBRL = 120
        store.update(changed)
        store.remove(id: subscription.id)

        XCTAssertEqual(store.history.map(\.kind), [.cancelled, .priceChanged, .renewalConfirmed])
        XCTAssertEqual(store.history.totalRenewed(in: .now), 100)
    }

    @MainActor
    func testMonthlySpendCombinesConfirmedPlansAndExtras() {
        let suite = "MonthlySpendTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SubscriptionStore(defaults: defaults, storageKey: "subscriptions")
        let plan = AISubscription(provider: .claude, planName: "Pro", basePriceBRL: 100, nextRenewalDate: .now)
        store.add(plan)
        _ = store.confirmRenewal(id: plan.id)
        store.addExpense(AIExpense(provider: .claude, title: "Usage credits", amountBRL: 25, kind: .usageCredits, source: .officialInvoice))

        XCTAssertEqual(store.monthlySpend.planChargesBRL, 100)
        XCTAssertEqual(store.monthlySpend.extraChargesBRL, 25)
        XCTAssertEqual(store.monthlySpend.totalBRL, 125)
    }

    func testMonthlySpendSeparatesForecastAndLocalEstimate() {
        let calendar = Calendar(identifier: .gregorian)
        let month = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        let renewal = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28))!
        let plan = AISubscription(provider: .claude, planName: "Pro", basePriceBRL: 100, nextRenewalDate: renewal)
        let estimated = AIExpense(provider: .claude, title: "Local", amountBRL: 20, kind: .apiUsage, source: .localEstimate, incurredAt: month)
        let official = AIExpense(provider: .claude, title: "Invoice", amountBRL: 30, kind: .apiUsage, source: .officialInvoice, incurredAt: month)

        let summary = MonthlySpendSummary(history: [], expenses: [estimated, official], subscriptions: [plan], month: month, calendar: calendar)

        XCTAssertEqual(summary.paidBRL, 30)
        XCTAssertEqual(summary.forecastPlanBRL, 100)
    }

    func testBudgetUsesPaidPlusForecastAndThresholds() {
        let summary = MonthlySpendSummary(
            history: [],
            expenses: [AIExpense(provider: .claude, title: "Credit", amountBRL: 250, kind: .usageCredits, source: .officialInvoice)],
            subscriptions: [AISubscription(provider: .claude, planName: "Pro", basePriceBRL: 200, nextRenewalDate: .now)]
        )
        let status = MonthlyBudgetStatus(summary: summary, budgetBRL: 500)

        XCTAssertEqual(status.projectedBRL, 450)
        XCTAssertEqual(status.projectedPercent, 90)
        XCTAssertEqual(status.level, .critical)
    }

    func testMonthlyHistoryIncludesConfirmedAndOfficialPaymentsOnly() {
        let calendar = Calendar(identifier: .gregorian)
        let july = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10))!
        let history = [SubscriptionHistoryEvent(subscriptionID: UUID(), provider: .claude, planName: "Pro", kind: .renewalConfirmed, amountBRL: 100, occurredAt: july)]
        let expenses = [
            AIExpense(provider: .claude, title: "Invoice", amountBRL: 25, kind: .apiUsage, source: .officialInvoice, incurredAt: july),
            AIExpense(provider: .claude, title: "Estimate", amountBRL: 10, kind: .apiUsage, source: .localEstimate, incurredAt: july),
        ]
        let rows = FinancialHistory.monthlyPayments(history: history, expenses: expenses, now: july, calendar: calendar)
        XCTAssertEqual(rows.first?.amountBRL, 125)
        XCTAssertTrue(FinancialHistory.csv(rows).contains("2026-07,claude,125"))
    }
}
