import Foundation

/// Appearance for all NotchAgent surfaces. Auto follows the system.
public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case auto
    case dark
    case light
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var themeMode: ThemeMode = .auto
    public var refreshIntervalSeconds: Double = 60
    /// Percent thresholds applied to any quota percentage a provider reports.
    public var warningThresholdPercent: Double = 70
    public var criticalThresholdPercent: Double = 90
    public var favoriteProvider: ProviderID?
    public var notchOverlayEnabled: Bool = true
    /// When the display has no notch, show a floating top pill instead of nothing.
    public var fallbackPillEnabled: Bool = true
    /// Probe the Anthropic API (max_tokens: 1) using the local Claude Code OAuth
    /// token to read the authoritative 5h/7d quota percentages from response
    /// headers. Falls back to token budgets when disabled or no token is found.
    public var claudeQuotaProbeEnabled: Bool = true
    /// System notifications when a provider crosses warning/critical
    /// (requires running from the .app bundle).
    public var notificationsEnabled: Bool = true
    /// Optional user-set budgets used only when the API probe is unavailable.
    public var claudeSessionTokenBudget: Int?
    public var claudeWeeklyTokenBudget: Int?

    public init() {}

    // Manual decode with defaults so persisted settings survive new fields.
    private enum CodingKeys: String, CodingKey {
        case themeMode
        case refreshIntervalSeconds
        case warningThresholdPercent
        case criticalThresholdPercent
        case favoriteProvider
        case notchOverlayEnabled
        case fallbackPillEnabled
        case claudeQuotaProbeEnabled
        case notificationsEnabled
        case claudeSessionTokenBudget
        case claudeWeeklyTokenBudget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeMode = try container.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .auto
        refreshIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds) ?? 60
        warningThresholdPercent = try container.decodeIfPresent(Double.self, forKey: .warningThresholdPercent) ?? 70
        criticalThresholdPercent = try container.decodeIfPresent(Double.self, forKey: .criticalThresholdPercent) ?? 90
        favoriteProvider = try container.decodeIfPresent(ProviderID.self, forKey: .favoriteProvider)
        notchOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .notchOverlayEnabled) ?? true
        fallbackPillEnabled = try container.decodeIfPresent(Bool.self, forKey: .fallbackPillEnabled) ?? true
        claudeQuotaProbeEnabled = try container.decodeIfPresent(Bool.self, forKey: .claudeQuotaProbeEnabled) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        claudeSessionTokenBudget = try container.decodeIfPresent(Int.self, forKey: .claudeSessionTokenBudget)
        claudeWeeklyTokenBudget = try container.decodeIfPresent(Int.self, forKey: .claudeWeeklyTokenBudget)
    }
}
