import Foundation

#if os(macOS)
import SwiftUI
import WebKit

/// Creates one persistent WebKit profile per configured API account. Cookies
/// remain inside WebKit and are never copied to Preferences, logs or Keychain.
@MainActor
enum APIAccountPortalSession {
    static func configuration(for accountID: UUID) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: accountID)
        return configuration
    }

    static func loginView(for account: APIAccount) -> WKWebView {
        switch account.service {
        case .anthropicAPI:
            return AnthropicAPIConsoleReader.makeLoginView(accountID: account.id)
        case .anthropicConsole:
            return AnthropicConsoleReader.makeLoginView(accountID: account.id)
        case .chatGPTSubscription:
            return ChatGPTSubscriptionReader.makeLoginView(accountID: account.id)
        case .googleSubscription:
            return GoogleSubscriptionReader.makeLoginView(accountID: account.id)
        case .firecrawlSubscription:
            return FirecrawlSubscriptionReader.makeLoginView(accountID: account.id)
        case .deepSeek:
            return DeepSeekConsoleReader.makeLoginView(accountID: account.id)
        case .gemini:
            return GoogleAIStudioConsoleReader.makeLoginView(
                accountID: account.id,
                projectID: account.identifier
            )
        case .openAI:
            return OpenAIConsoleReader.makeLoginView(accountID: account.id)
        case .openRouter:
            return OpenRouterConsoleReader.makeLoginView(accountID: account.id)
        case .twitterAPI:
            return TwitterAPIIOConsoleReader.makeLoginView(accountID: account.id)
        case .xTwitter, .xTwitterAccount1, .xTwitterAccount2:
            return XDeveloperConsoleReader.makeLoginView(accountID: account.id)
        default:
            return WKWebView(frame: .zero, configuration: configuration(for: account.id))
        }
    }

    static func disconnect(accountID: UUID) async {
        let store = WKWebsiteDataStore(forIdentifier: accountID)
        await withCheckedContinuation { continuation in
            store.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }
}

struct APIAccountPortalLoginView: NSViewRepresentable {
    let account: APIAccount

    func makeNSView(context: Context) -> WKWebView {
        APIAccountPortalSession.loginView(for: account)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
