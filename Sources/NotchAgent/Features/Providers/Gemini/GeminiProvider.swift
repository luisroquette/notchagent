import Foundation

/// Partially supported provider: Gemini CLI does not persist token usage locally,
/// so health/activity are real and token fields stay nil (never fabricated).
struct GeminiProvider: UsageProvider {
    let id = ProviderID.geminiCLI
    let capabilities: ProviderCapabilities = []

    private let root: URL
    private let cache = FileScanCache<GeminiLogStat>()

    init(root: URL = AppPaths.home.appendingPathComponent(".gemini")) {
        self.root = root
    }

    func detectInstallation() -> ProviderInstallation {
        FileManager.default.fileExists(atPath: root.path)
            ? .installed(dataPath: root.path)
            : .notInstalled
    }

    func fetchSnapshot(settings: AppSettings) async throws -> UsageSnapshot {
        let now = Date()
        guard case .installed = detectInstallation() else {
            return UsageSnapshot(provider: id, health: .notInstalled)
        }

        let tmp = root.appendingPathComponent("tmp")
        let projectDirs = (try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        var prompts7d = 0
        var promptsToday = 0
        var sessions = Set<String>()
        var lastActivity: Date?
        var failedFiles = 0

        let weekCutoff = now.addingTimeInterval(-7 * 24 * 3600)
        let dayStart = now.flooredToDay

        for dir in projectDirs {
            let logFile = dir.appendingPathComponent("logs.json")
            guard FileManager.default.fileExists(atPath: logFile.path) else { continue }
            do {
                guard let stat = try await cache.value(for: logFile, parse: { try GeminiLogParser.parseLogFile(at: $0) })
                else { continue }
                prompts7d += stat.promptTimestamps.filter { $0 >= weekCutoff }.count
                promptsToday += stat.promptTimestamps.filter { $0 >= dayStart }.count
                sessions.formUnion(stat.sessionIDs)
                if let activity = stat.lastActivity, lastActivity.map({ activity > $0 }) ?? true {
                    lastActivity = activity
                }
            } catch {
                failedFiles += 1
                Log.providers.error("gemini: failed to parse \(logFile.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        let scanned = projectDirs.map { $0.appendingPathComponent("logs.json").path }
        await cache.prune(keeping: Set(scanned))

        let health: ProviderHealth
        if prompts7d == 0 && lastActivity == nil {
            health = failedFiles > 0 ? .parseError : .noData
        } else {
            health = failedFiles > 0 ? .degraded : .ok
        }

        return UsageSnapshot(
            provider: id,
            capturedAt: now,
            health: health,
            lastActivityAt: lastActivity,
            note: health == .ok || health == .degraded
                ? "\(promptsToday) prompts today · \(prompts7d) in 7 days — token data not exposed by Gemini CLI"
                : "Token data not exposed by Gemini CLI"
        )
    }
}
