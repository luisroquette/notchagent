import Foundation

public enum AttentionLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    case normal = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: AttentionLevel, rhs: AttentionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

public struct ProviderAlert: Sendable, Equatable {
    public var provider: ProviderID
    public var level: AttentionLevel
    public var message: String
    public var date: Date

    public init(provider: ProviderID, level: AttentionLevel, message: String, date: Date = Date()) {
        self.provider = provider
        self.level = level
        self.message = message
        self.date = date
    }
}

public struct UsageEvent: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case alert
        case error
        case info
    }

    public var id: UUID
    public var date: Date
    public var provider: ProviderID?
    public var kind: Kind
    public var level: AttentionLevel
    public var message: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        provider: ProviderID? = nil,
        kind: Kind,
        level: AttentionLevel = .normal,
        message: String
    ) {
        self.id = id
        self.date = date
        self.provider = provider
        self.kind = kind
        self.level = level
        self.message = message
    }
}

public enum RefreshState: Sendable, Equatable {
    case idle
    case refreshing
    case success(Date)
    case failure(Date, String)
}
