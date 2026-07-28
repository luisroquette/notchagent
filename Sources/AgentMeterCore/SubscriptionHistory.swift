import Foundation

public enum SubscriptionHistoryKind: String, Codable, Sendable, Equatable {
    case imported
    case priceChanged
    case renewalConfirmed
    case cancelled
}

public struct SubscriptionHistoryEvent: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var subscriptionID: UUID
    public var provider: AgentMeterProvider
    public var planName: String
    public var kind: SubscriptionHistoryKind
    public var amountBRL: Decimal
    public var occurredAt: Date

    public init(
        id: UUID = UUID(),
        subscriptionID: UUID,
        provider: AgentMeterProvider,
        planName: String,
        kind: SubscriptionHistoryKind,
        amountBRL: Decimal,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.provider = provider
        self.planName = planName
        self.kind = kind
        self.amountBRL = amountBRL
        self.occurredAt = occurredAt
    }
}

public extension Array where Element == SubscriptionHistoryEvent {
    func totalRenewed(in month: Date, calendar: Calendar = .current) -> Decimal {
        filter {
            $0.kind == .renewalConfirmed && calendar.isDate($0.occurredAt, equalTo: month, toGranularity: .month)
        }
        .reduce(0) { $0 + $1.amountBRL }
    }
}
