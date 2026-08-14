import Foundation

enum CodexOnboardingStatus: Equatable {
    case notInstalled
    case notAuthenticated
    case noSession
    case ready

    static func classify(
        cliInstalled: Bool,
        authenticated: Bool,
        hasSession: Bool
    ) -> Self {
        guard cliInstalled else { return .notInstalled }
        guard authenticated else { return .notAuthenticated }
        guard hasSession else { return .noSession }
        return .ready
    }

    var action: CodexOnboardingAction? {
        switch self {
        case .notInstalled: .openInstallGuide
        case .notAuthenticated: .authenticate
        case .noSession: .createFirstSession
        case .ready: nil
        }
    }
}

enum CodexOnboardingAction: Equatable {
    case openInstallGuide
    case authenticate
    case createFirstSession
}

struct CodexProcessInvocation: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
}

enum CodexOnboardingLaunchError: Error {
    case codexNotInstalled
    case commandFailed
}

struct CodexOnboardingInspector {
    static var sessionsURL: URL {
        AppPaths.home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    static func executableURL(fileManager: FileManager = .default) -> URL? {
        let home = AppPaths.home
        let candidates = [
            home.appendingPathComponent(".npm-global/bin/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func inspect() async -> CodexOnboardingStatus {
        guard let executable = executableURL() else { return .notInstalled }
        let authenticated = await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["login", "status"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
        let hasSession = hasSession(at: sessionsURL)
        return .classify(
            cliInstalled: true,
            authenticated: authenticated,
            hasSession: hasSession
        )
    }

    static func hasSession(
        at root: URL,
        now: Date = Date()
    ) -> Bool {
        let files = recentFiles(
            under: root,
            ext: "jsonl",
            modifiedAfter: now.addingTimeInterval(-8 * 24 * 3600),
            limit: 100
        )
        return files.contains { url in
            url.lastPathComponent.hasPrefix("rollout-")
                && (try? CodexRolloutParser.latestTokenInfo(at: url)) != nil
        }
    }

    static func loginInvocation(executable: URL) -> CodexProcessInvocation {
        CodexProcessInvocation(executableURL: executable, arguments: ["login"])
    }

    static func firstSessionInvocation(executable: URL) -> CodexProcessInvocation {
        CodexProcessInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", "Terminal", executable.path]
        )
    }

    static func beginLogin() async throws {
        guard let executable = executableURL() else {
            throw CodexOnboardingLaunchError.codexNotInstalled
        }
        guard try await run(loginInvocation(executable: executable)) == 0 else {
            throw CodexOnboardingLaunchError.commandFailed
        }
    }

    static func beginFirstSession() async throws {
        guard let executable = executableURL() else {
            throw CodexOnboardingLaunchError.codexNotInstalled
        }
        guard try await run(firstSessionInvocation(executable: executable)) == 0 else {
            throw CodexOnboardingLaunchError.commandFailed
        }
    }

    static func waitForStateChange(
        from initial: CodexOnboardingStatus,
        attempts: Int = 60,
        interval: Duration = .seconds(2)
    ) async -> CodexOnboardingStatus {
        var latest = initial
        for _ in 0..<max(1, attempts) {
            latest = await inspect()
            if latest != initial { return latest }
            try? await Task.sleep(for: interval)
        }
        return latest
    }

    private static func run(_ invocation: CodexProcessInvocation) async throws -> Int32 {
        try await Task.detached {
            let process = Process()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }
}
