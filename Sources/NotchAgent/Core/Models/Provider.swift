import Foundation

/// Stable identifier for each monitored AI provider.
public enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case geminiCLI = "gemini-cli"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        }
    }

    public var shortName: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        case .geminiCLI: "Gemini"
        }
    }

    /// SF Symbol used across the UI.
    public var symbolName: String {
        switch self {
        case .claudeCode: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .geminiCLI: "sparkle"
        }
    }
}

/// What a provider can actually report, so the UI never renders fake data.
public struct ProviderCapabilities: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let sessionTokens = ProviderCapabilities(rawValue: 1 << 0)
    public static let sessionPercent = ProviderCapabilities(rawValue: 1 << 1)
    public static let weeklyTokens = ProviderCapabilities(rawValue: 1 << 2)
    public static let weeklyPercent = ProviderCapabilities(rawValue: 1 << 3)
    public static let costEstimate = ProviderCapabilities(rawValue: 1 << 4)
    public static let resetSchedule = ProviderCapabilities(rawValue: 1 << 5)
}

public enum ProviderInstallation: Codable, Sendable, Equatable {
    case installed(dataPath: String)
    case notInstalled
}

public enum ProviderHealth: String, Codable, Sendable, Equatable {
    /// Data parsed successfully.
    case ok
    /// Some files failed to parse but a snapshot was still produced.
    case degraded
    /// Nothing could be parsed.
    case parseError
    /// The provider's data directory does not exist on this machine.
    case notInstalled
    /// Installed but no usage data found in the lookback window.
    case noData

    public var isUsable: Bool { self == .ok || self == .degraded || self == .noData }
}
