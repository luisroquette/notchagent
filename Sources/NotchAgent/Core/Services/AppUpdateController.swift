import Foundation
import Sparkle

@MainActor
final class AppUpdateController {
    private let controller: SPUStandardUpdaterController?

    var isConfigured: Bool { controller != nil }

    init(bundle: Bundle = .main) {
        guard BundleContext.isBundledApp,
              let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed),
              url.scheme == "https",
              bundle.object(forInfoDictionaryKey: "SUPublicEDKey") is String
        else {
            controller = nil
            return
        }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
