import Foundation

public enum BillingCycle: String, CaseIterable, Codable, Sendable, Identifiable {
    case monthly
    case yearly

    public var id: String { rawValue }
}

public struct AISubscription: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var provider: AgentMeterProvider
    public var planName: String
    public var basePriceBRL: Decimal
    public var taxPercentage: Decimal
    public var billingCycle: BillingCycle
    public var nextRenewalDate: Date
    public var reminderDaysBefore: Int
    public var isActive: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        provider: AgentMeterProvider,
        planName: String,
        basePriceBRL: Decimal,
        taxPercentage: Decimal = 0,
        billingCycle: BillingCycle = .monthly,
        nextRenewalDate: Date,
        reminderDaysBefore: Int = 3,
        isActive: Bool = true,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.provider = provider
        self.planName = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.basePriceBRL = max(basePriceBRL, 0)
        self.taxPercentage = max(taxPercentage, 0)
        self.billingCycle = billingCycle
        self.nextRenewalDate = nextRenewalDate
        self.reminderDaysBefore = max(reminderDaysBefore, 0)
        self.isActive = isActive
        self.updatedAt = updatedAt
    }

    public var cycleTotalBRL: Decimal {
        basePriceBRL * (1 + taxPercentage / 100)
    }

    public var monthlyEquivalentBRL: Decimal {
        billingCycle == .monthly ? cycleTotalBRL : cycleTotalBRL / 12
    }

    public var projectedAnnualBRL: Decimal {
        billingCycle == .monthly ? cycleTotalBRL * 12 : cycleTotalBRL
    }

    public func daysUntilRenewal(referenceDate: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: referenceDate)
        let renewal = calendar.startOfDay(for: nextRenewalDate)
        return calendar.dateComponents([.day], from: start, to: renewal).day ?? 0
    }

    public func needsRenewalAttention(referenceDate: Date = .now, calendar: Calendar = .current) -> Bool {
        let days = daysUntilRenewal(referenceDate: referenceDate, calendar: calendar)
        return isActive && days >= 0 && days <= reminderDaysBefore
    }

    /// Advances the subscription from its scheduled renewal date, preserving
    /// the billing cadence even when the confirmation happens early or late.
    public func nextRenewal(after confirmationDate: Date = .now, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = billingCycle == .monthly ? .month : .year
        var candidate = calendar.date(byAdding: component, value: 1, to: nextRenewalDate) ?? nextRenewalDate
        while candidate <= confirmationDate {
            guard let following = calendar.date(byAdding: component, value: 1, to: candidate) else { break }
            candidate = following
        }
        return candidate
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, planName, basePriceBRL, taxPercentage, billingCycle
        case nextRenewalDate, reminderDaysBefore, isActive, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        provider = try values.decode(AgentMeterProvider.self, forKey: .provider)
        planName = try values.decode(String.self, forKey: .planName)
        basePriceBRL = try values.decode(Decimal.self, forKey: .basePriceBRL)
        taxPercentage = try values.decode(Decimal.self, forKey: .taxPercentage)
        billingCycle = try values.decode(BillingCycle.self, forKey: .billingCycle)
        nextRenewalDate = try values.decode(Date.self, forKey: .nextRenewalDate)
        reminderDaysBefore = try values.decode(Int.self, forKey: .reminderDaysBefore)
        isActive = try values.decode(Bool.self, forKey: .isActive)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

public struct SubscriptionSyncSnapshot: Codable, Equatable, Sendable {
    public var subscriptions: [AISubscription]
    public var tombstones: [UUID: Date]
    public var history: [SubscriptionHistoryEvent]

    public init(
        subscriptions: [AISubscription],
        tombstones: [UUID: Date] = [:],
        history: [SubscriptionHistoryEvent] = []
    ) {
        self.subscriptions = subscriptions
        self.tombstones = tombstones
        self.history = history
    }

    public func merged(with other: SubscriptionSyncSnapshot) -> SubscriptionSyncSnapshot {
        var subscriptionsByID: [UUID: AISubscription] = [:]
        for subscription in subscriptions + other.subscriptions {
            if let current = subscriptionsByID[subscription.id], current.updatedAt >= subscription.updatedAt {
                continue
            }
            subscriptionsByID[subscription.id] = subscription
        }

        var mergedTombstones = tombstones
        for (id, date) in other.tombstones where date > (mergedTombstones[id] ?? .distantPast) {
            mergedTombstones[id] = date
        }

        var revivedIDs: [UUID] = []
        for (id, deletedAt) in mergedTombstones {
            if let subscription = subscriptionsByID[id], deletedAt >= subscription.updatedAt {
                subscriptionsByID.removeValue(forKey: id)
            } else if subscriptionsByID[id] != nil {
                revivedIDs.append(id)
            }
        }
        revivedIDs.forEach { mergedTombstones.removeValue(forKey: $0) }

        var events: [UUID: SubscriptionHistoryEvent] = [:]
        for event in history + other.history where events[event.id] == nil {
            events[event.id] = event
        }

        return SubscriptionSyncSnapshot(
            subscriptions: subscriptionsByID.values.sorted { $0.nextRenewalDate < $1.nextRenewalDate },
            tombstones: mergedTombstones,
            history: events.values.sorted { $0.occurredAt > $1.occurredAt }
        )
    }

    private enum CodingKeys: String, CodingKey { case subscriptions, tombstones, history }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try values.decode([AISubscription].self, forKey: .subscriptions)
        tombstones = try values.decodeIfPresent([UUID: Date].self, forKey: .tombstones) ?? [:]
        history = try values.decodeIfPresent([SubscriptionHistoryEvent].self, forKey: .history) ?? []
    }
}

public struct SubscriptionSummary: Equatable, Sendable {
    public var activeCount: Int
    public var monthlyTotalBRL: Decimal
    public var projectedAnnualBRL: Decimal
    public var upcomingRenewals: [AISubscription]

    public init(subscriptions: [AISubscription], referenceDate: Date = .now) {
        let active = subscriptions.filter(\.isActive)
        activeCount = active.count
        monthlyTotalBRL = active.reduce(0) { $0 + $1.monthlyEquivalentBRL }
        projectedAnnualBRL = active.reduce(0) { $0 + $1.projectedAnnualBRL }
        upcomingRenewals = active
            .filter { $0.needsRenewalAttention(referenceDate: referenceDate) }
            .sorted { $0.nextRenewalDate < $1.nextRenewalDate }
    }
}
