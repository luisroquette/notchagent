import Foundation

/// Appearance for all NotchAgent surfaces. Auto follows the system.
public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case auto
    case dark
    case light
}

public enum InterfaceLanguage: String, Codable, Sendable, CaseIterable {
    case ptBR
    case en

    var label: String { self == .ptBR ? "Português (Brasil)" : "English" }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var interfaceLanguage: InterfaceLanguage = .ptBR
    public var themeMode: ThemeMode = .auto
    public var refreshIntervalSeconds: Double = 60
    /// Percent thresholds applied to any quota percentage a provider reports.
    public var warningThresholdPercent: Double = 70
    public var criticalThresholdPercent: Double = 90
    public var favoriteProvider: ProviderID?
    public var notchOverlayEnabled: Bool = true
    /// When the display has no notch, show a floating top pill instead of nothing.
    public var fallbackPillEnabled: Bool = true
    /// Pixel Clawd running a dino-game track across the compact bar.
    public var runnerEnabled: Bool = true
    /// Remaining-percent milestones that trigger quota alert takeovers.
    public var quotaAlertThresholdPercents: [Int] = [100, 75, 50, 25, 5]
    /// Opt-in mirroring of sanitized usage snapshots. Desk discovery, firmware
    /// identity, and local hardware telemetry remain automatic.
    public var notchAgentDeskEnabled: Bool = false
    /// Set only after the user explicitly enables Desk usage mirroring. It is
    /// used to avoid repeatedly presenting first-connection onboarding.
    public var notchAgentDeskOnboardingCompleted: Bool = false
    /// Probe the Anthropic API (max_tokens: 1) using the local Claude Code OAuth
    /// token to read the authoritative 5h/7d quota percentages from response
    /// headers. Falls back to token budgets when disabled or no token is found.
    public var claudeQuotaProbeEnabled: Bool = false
    /// Consent schema for the network probe. Legacy persisted `true` values
    /// predate the explicit-cost disclosure and are deliberately not trusted.
    public var claudeQuotaProbeConsentVersion: Int = 0
    /// Opt-in account monitors. No network request is made until this is true
    /// and at least one service is selected.
    public var apiAccountMonitoringEnabled: Bool = false
    /// User-created API accounts. One service can appear multiple times.
    public var apiAccounts: [APIAccount] = []
    /// Legacy fields are retained solely to migrate settings from v1.
    public var monitoredAPIServices: Set<APIServiceID> = []
    /// Non-secret account context (for example a Google Cloud project ID).
    /// Credentials always remain in Keychain.
    public var apiAccountIdentifiers: [APIServiceID: String] = [:]
    /// System notifications when a provider crosses warning/critical
    /// (requires running from the .app bundle).
    public var notificationsEnabled: Bool = true
    /// Optional user-set budgets used only when the API probe is unavailable.
    public var claudeSessionTokenBudget: Int?
    public var claudeWeeklyTokenBudget: Int?
    /// Codex Pro rollouts never report a 5h window, so the session percent is
    /// estimated from this user-set budget (nil = keep showing session tokens).
    public var codexSessionTokenBudget: Int?
    /// One-time migration that creates independent web-only subscription
    /// slots. Removing one later remains a user decision.
    var webSubscriptionAccountsInitialized: Bool = false
    /// Added after the original web-subscription migration so existing users
    /// receive one Firecrawl subscription slot without recreating removed ones.
    var firecrawlSubscriptionAccountInitialized: Bool = false

    public init() {}

    // Manual decode with defaults so persisted settings survive new fields.
    private enum CodingKeys: String, CodingKey {
        case themeMode
        case interfaceLanguage
        case refreshIntervalSeconds
        case warningThresholdPercent
        case criticalThresholdPercent
        case favoriteProvider
        case notchOverlayEnabled
        case fallbackPillEnabled
        case runnerEnabled
        case quotaAlertThresholdPercents
        case notchAgentDeskEnabled
        case notchAgentDeskOnboardingCompleted
        case claudeQuotaProbeEnabled
        case claudeQuotaProbeConsentVersion
        case apiAccountMonitoringEnabled
        case apiAccounts
        case monitoredAPIServices
        case apiAccountIdentifiers
        case notificationsEnabled
        case claudeSessionTokenBudget
        case claudeWeeklyTokenBudget
        case codexSessionTokenBudget
        case webSubscriptionAccountsInitialized
        case firecrawlSubscriptionAccountInitialized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeMode = try container.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .auto
        interfaceLanguage = try container.decodeIfPresent(InterfaceLanguage.self, forKey: .interfaceLanguage) ?? .ptBR
        refreshIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds) ?? 60
        warningThresholdPercent = try container.decodeIfPresent(Double.self, forKey: .warningThresholdPercent) ?? 70
        criticalThresholdPercent = try container.decodeIfPresent(Double.self, forKey: .criticalThresholdPercent) ?? 90
        favoriteProvider = try container.decodeIfPresent(ProviderID.self, forKey: .favoriteProvider)
        notchOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .notchOverlayEnabled) ?? true
        fallbackPillEnabled = try container.decodeIfPresent(Bool.self, forKey: .fallbackPillEnabled) ?? true
        runnerEnabled = try container.decodeIfPresent(Bool.self, forKey: .runnerEnabled) ?? true
        quotaAlertThresholdPercents = ThresholdAlerts.normalized(
            try container.decodeIfPresent([Int].self, forKey: .quotaAlertThresholdPercents)
                ?? ThresholdAlerts.defaultLevels
        )
        notchAgentDeskEnabled = try container.decodeIfPresent(Bool.self, forKey: .notchAgentDeskEnabled) ?? false
        notchAgentDeskOnboardingCompleted = try container.decodeIfPresent(
            Bool.self,
            forKey: .notchAgentDeskOnboardingCompleted
        ) ?? notchAgentDeskEnabled
        claudeQuotaProbeConsentVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .claudeQuotaProbeConsentVersion
        ) ?? 0
        let persistedQuotaProbe = try container.decodeIfPresent(
            Bool.self,
            forKey: .claudeQuotaProbeEnabled
        ) ?? false
        claudeQuotaProbeEnabled = persistedQuotaProbe && claudeQuotaProbeConsentVersion >= 1
        apiAccountMonitoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .apiAccountMonitoringEnabled) ?? false
        monitoredAPIServices = try container.decodeIfPresent(Set<APIServiceID>.self, forKey: .monitoredAPIServices) ?? []
        apiAccountIdentifiers = try container.decodeIfPresent([APIServiceID: String].self, forKey: .apiAccountIdentifiers) ?? [:]
        apiAccounts = try container.decodeIfPresent([APIAccount].self, forKey: .apiAccounts) ?? monitoredAPIServices
            .sorted { $0.displayName < $1.displayName }
            .map { service in
                let normalizedService: APIServiceID = (service == .xTwitterAccount1 || service == .xTwitterAccount2) ? .xTwitter : service
                return APIAccount(
                    service: normalizedService,
                    label: service.displayName,
                    identifier: apiAccountIdentifiers[service] ?? "",
                    keychainAccount: service.rawValue
                )
            }
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        claudeSessionTokenBudget = try container.decodeIfPresent(Int.self, forKey: .claudeSessionTokenBudget)
        claudeWeeklyTokenBudget = try container.decodeIfPresent(Int.self, forKey: .claudeWeeklyTokenBudget)
        codexSessionTokenBudget = try container.decodeIfPresent(Int.self, forKey: .codexSessionTokenBudget)
        webSubscriptionAccountsInitialized = try container.decodeIfPresent(
            Bool.self,
            forKey: .webSubscriptionAccountsInitialized
        ) ?? false
        firecrawlSubscriptionAccountInitialized = try container.decodeIfPresent(
            Bool.self,
            forKey: .firecrawlSubscriptionAccountInitialized
        ) ?? false
        ensureAnthropicAPIAccountIfNeeded()
    }

    public mutating func migrateLegacyAPIAccountsIfNeeded() {
        guard apiAccounts.isEmpty, !monitoredAPIServices.isEmpty else { return }
        apiAccounts = monitoredAPIServices.sorted { $0.displayName < $1.displayName }.map { service in
            let normalizedService: APIServiceID = (service == .xTwitterAccount1 || service == .xTwitterAccount2) ? .xTwitter : service
            return APIAccount(
                service: normalizedService,
                label: service.displayName,
                identifier: apiAccountIdentifiers[service] ?? "",
                keychainAccount: service.rawValue
            )
        }
        normalizeAPIAccountLabels()
        ensureAnthropicAPIAccountIfNeeded()
    }

    public mutating func normalizeAPIAccountLabels() {
        for index in apiAccounts.indices where apiAccounts[index].service == .anthropicConsole {
            let oldLabel = apiAccounts[index].label.lowercased()
            if oldLabel == "openai" || oldLabel == "anthropic console" {
                apiAccounts[index].label = APIServiceID.anthropicConsole.displayName
            }
        }
    }

    /// Claude subscriptions and Anthropic API organizations are separate
    /// products. Existing Claude-connected users get an explicit API slot
    /// without reclassifying or reusing their subscription credentials.
    public mutating func ensureAnthropicAPIAccountIfNeeded() {
        guard apiAccounts.contains(where: { $0.service == .anthropicConsole }),
              !apiAccounts.contains(where: { $0.service == .anthropicAPI })
        else { return }
        apiAccounts.append(APIAccount(service: .anthropicAPI))
    }

    /// Subscriptions bought on vendor websites get isolated browser profiles
    /// and never reuse API credentials or contribute to API spend totals.
    public mutating func ensureWebSubscriptionAccountsIfNeeded() {
        if !webSubscriptionAccountsInitialized {
            for service in [
                APIServiceID.anthropicConsole,
                .chatGPTSubscription,
                .googleSubscription,
            ] where !apiAccounts.contains(where: { $0.service == service }) {
                apiAccounts.append(APIAccount(service: service))
            }
            webSubscriptionAccountsInitialized = true
        }
        if !firecrawlSubscriptionAccountInitialized {
            if !apiAccounts.contains(where: { $0.service == .firecrawlSubscription }) {
                let fallback = apiAccounts.first(where: { $0.service == .firecrawl })?.monthlyPlanBRL
                apiAccounts.append(APIAccount(
                    service: .firecrawlSubscription,
                    monthlyPlanBRL: fallback
                ))
            }
            firecrawlSubscriptionAccountInitialized = true
        }
        ensureAnthropicAPIAccountIfNeeded()
    }
}
