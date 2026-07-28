import Foundation

/// API accounts that NotchAgent can track without inspecting application data.
/// Credentials are deliberately stored separately in the Keychain; this type
/// is safe to persist in Preferences and history.
public enum APIServiceID: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case openAI = "openai"
    case gemini = "gemini"
    case xAI = "xai"
    case deepSeek = "deepseek"
    case elevenLabs = "elevenlabs"
    case firecrawl
    case heyGen = "heygen"
    case twilio
    case openRouter = "openrouter"
    case anthropicAPI = "anthropic-api"
    case anthropicConsole = "anthropic-console"
    case chatGPTSubscription = "chatgpt-subscription"
    case googleSubscription = "google-subscription"
    case firecrawlSubscription = "firecrawl-subscription"
    case xTwitter = "x-twitter"
    /// Legacy fixed slots; retained so existing settings remain readable.
    case xTwitterAccount1 = "x-twitter-account-1"
    case xTwitterAccount2 = "x-twitter-account-2"
    case twitterAPI = "twitterapi-io"
    case infoSimples = "infosimples"
    case brAPI = "brapi-dev"
    case logoDev = "logo-dev"
    case higgsfield
    case artificialAnalysis = "artificial-analysis"
    case swen

    public var id: String { rawValue }

    public static var addableCases: [APIServiceID] {
        allCases.filter {
            $0 != .xTwitterAccount1
                && $0 != .xTwitterAccount2
                && !$0.isSubscriptionService
        }
    }

    /// Consumer/team subscriptions are recurring products, never API usage.
    public var isSubscriptionService: Bool {
        switch self {
        case .anthropicConsole, .chatGPTSubscription, .googleSubscription, .firecrawlSubscription:
            true
        default:
            false
        }
    }

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Google / Gemini"
        case .xAI: "xAI / Grok (opcional)"
        case .deepSeek: "DeepSeek"
        case .elevenLabs: "ElevenLabs"
        case .firecrawl: "Firecrawl"
        case .heyGen: "HeyGen"
        case .twilio: "Twilio"
        case .openRouter: "OpenRouter"
        case .anthropicAPI: "Anthropic API"
        case .anthropicConsole: "Claude / Claude Code"
        case .chatGPTSubscription: "ChatGPT"
        case .googleSubscription: "Google AI / Gemini"
        case .firecrawlSubscription: "Firecrawl"
        case .xTwitter: "X / Twitter"
        case .xTwitterAccount1: "X / Twitter — Conta 1"
        case .xTwitterAccount2: "X / Twitter — Conta 2"
        case .twitterAPI: "twitterapi.io"
        case .infoSimples: "Infosimples"
        case .brAPI: "brapi.dev"
        case .logoDev: "logo.dev"
        case .higgsfield: "Higgsfield"
        case .artificialAnalysis: "Artificial Analysis"
        case .swen: "swen.ia.br"
        }
    }

    /// Canonical public domain used only for the Logo.dev image CDN.
    /// No account metadata or API usage is sent with this request.
    public var logoDomain: String {
        switch self {
        case .anthropicAPI, .anthropicConsole: "anthropic.com"
        case .openAI, .chatGPTSubscription: "openai.com"
        case .gemini, .googleSubscription: "google.com"
        case .xAI: "x.ai"
        case .deepSeek: "deepseek.com"
        case .elevenLabs: "elevenlabs.io"
        case .firecrawl, .firecrawlSubscription: "firecrawl.dev"
        case .heyGen: "heygen.com"
        case .twilio: "twilio.com"
        case .openRouter: "openrouter.ai"
        case .xTwitter, .xTwitterAccount1, .xTwitterAccount2: "x.com"
        case .twitterAPI: "twitterapi.io"
        case .infoSimples: "infosimples.com"
        case .brAPI: "brapi.dev"
        case .logoDev: "logo.dev"
        case .higgsfield: "higgsfield.ai"
        case .artificialAnalysis: "artificialanalysis.ai"
        case .swen: "swen.ia.br"
        }
    }

    public var logoMonogram: String {
        displayName
            .replacingOccurrences(of: " ", with: "")
            .prefix(2)
            .uppercased()
    }

    /// Describes what the upstream vendor exposes, avoiding a fabricated
    /// percentage when it only offers usage or rate-limit headers.
    public var monitoringKind: String {
        switch self {
        case .elevenLabs, .deepSeek, .firecrawl, .heyGen, .twilio, .openRouter, .twitterAPI:
            "credit or quota"
        case .openAI, .gemini, .xAI, .anthropicAPI:
            "usage or rate limit"
        case .anthropicConsole, .chatGPTSubscription, .googleSubscription, .firecrawlSubscription:
            "subscription usage and credits"
        case .xTwitter, .xTwitterAccount1, .xTwitterAccount2:
            "Bearer Token stored locally"
        case .infoSimples, .brAPI, .logoDev, .higgsfield, .artificialAnalysis, .swen:
            "needs endpoint configuration"
        }
    }

    /// A non-secret value required to address the vendor's account endpoint.
    public var identifierLabel: String? {
        switch self {
        case .gemini: "Google Cloud project ID"
        case .twilio: "Twilio Account SID"
        case .infoSimples, .brAPI, .logoDev, .higgsfield, .artificialAnalysis, .swen:
            "Read-only metrics endpoint"
        default: nil
        }
    }

    public var credentialPlaceholder: String {
        switch self {
        case .twilio: "Twilio API Key SID:secret"
        case .openAI: "OpenAI Admin key"
        case .anthropicAPI: "Anthropic Admin API key — opcional"
        case .xAI: "xAI Management key"
        case .gemini: "Google OAuth access token — optional fallback"
        case .xTwitter, .xTwitterAccount1, .xTwitterAccount2: "X API Bearer Token"
        case .anthropicConsole: "No API key — connect your Claude account"
        case .chatGPTSubscription: "No API key — connect your ChatGPT account"
        case .googleSubscription: "No API key — connect your Google account"
        case .firecrawlSubscription: "No API key — connect your Firecrawl account"
        case .higgsfield: "Higgsfield API Key ID:secret"
        default: "\(displayName) API key"
        }
    }

    /// Browser login is reserved for totals that the vendor's API does not
    /// expose. Each configured account gets an isolated WebKit profile.
    public var supportsPortalConnection: Bool {
        switch self {
        case .anthropicAPI, .anthropicConsole, .chatGPTSubscription, .googleSubscription,
             .firecrawlSubscription,
             .deepSeek, .openAI, .openRouter, .twitterAPI, .gemini,
             .xTwitter, .xTwitterAccount1, .xTwitterAccount2:
            true
        default:
            false
        }
    }
}
