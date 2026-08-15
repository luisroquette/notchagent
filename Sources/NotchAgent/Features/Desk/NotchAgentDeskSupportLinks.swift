import Foundation

enum NotchAgentDeskSupportLinks {
    static let setupGuide = requiredURL("https://cfgauss.com.br/notchagent/instalar")
    static let codexInstallGuide = requiredURL("https://developers.openai.com/codex/cli")

    private static func requiredURL(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid NotchAgent Desk support URL: \(value)")
        }
        return url
    }
}
