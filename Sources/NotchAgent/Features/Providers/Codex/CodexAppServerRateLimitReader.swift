import Foundation

/// Reads the authenticated quota surface used by first-party Codex clients.
/// This starts no model turn and makes no paid inference request.
actor CodexAppServerRateLimitReader {
    static let shared = CodexAppServerRateLimitReader()

    private let executableURL: URL?
    private let minInterval: TimeInterval
    private var cached: [String: CodexTokenInfo]?
    private var lastAttempt = Date.distantPast

    init(
        executableURL: URL? = CodexAppServerRateLimitReader.defaultExecutableURL(),
        minInterval: TimeInterval = 60
    ) {
        self.executableURL = executableURL
        self.minInterval = minInterval
    }

    private static func defaultExecutableURL(fileManager: FileManager = .default) -> URL? {
        let bundled = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        return fileManager.isExecutableFile(atPath: bundled.path)
            ? bundled
            : CodexOnboardingInspector.executableURL(fileManager: fileManager)
    }

    func currentLimits(now: Date = Date()) async -> [String: CodexTokenInfo]? {
        if now.timeIntervalSince(lastAttempt) < minInterval { return cached }
        lastAttempt = now
        guard let executableURL else { return cached }

        do {
            if let fresh = try await Self.fetch(executableURL: executableURL, now: now) {
                cached = fresh
            }
        } catch {
            Log.providers.info("codex app-server quota unavailable: \(error.localizedDescription, privacy: .public)")
        }
        return cached
    }

    static func parseResponse(_ data: Data, now: Date = Date()) -> [String: CodexTokenInfo]? {
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A).reversed() {
            guard let envelope = try? decoder.decode(Envelope.self, from: Data(line)),
                  envelope.id == 2,
                  let result = envelope.result
            else { continue }

            let buckets: [String: Bucket]
            if let byID = result.rateLimitsByLimitId, !byID.isEmpty {
                buckets = byID
            } else if let bucket = result.rateLimits {
                buckets = [bucket.limitId ?? CodexProvider.sharedLimitID: bucket]
            } else {
                return nil
            }

            return buckets.reduce(into: [:]) { parsed, entry in
                let bucket = entry.value
                let key = bucket.limitId ?? entry.key
                parsed[key] = CodexTokenInfo(
                    timestamp: now,
                    totals: .zero,
                    primary: window(bucket.primary),
                    secondary: window(bucket.secondary),
                    planType: bucket.planType,
                    limitID: key,
                    limitName: bucket.limitName
                )
            }
        }
        return nil
    }

    private static func fetch(executableURL: URL, now: Date) async throws -> [String: CodexTokenInfo]? {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = executableURL
            process.arguments = ["app-server"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()

            let buffer = LockedData()
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { buffer.append(data) }
            }

            let requests = """
            {"method":"initialize","id":1,"params":{"clientInfo":{"name":"notchagent","title":"NotchAgent","version":"1"}}}
            {"method":"initialized","params":{}}
            {"method":"account/rateLimits/read","id":2}

            """
            try input.fileHandleForWriting.write(contentsOf: Data(requests.utf8))

            let deadline = Date().addingTimeInterval(8)
            var result: [String: CodexTokenInfo]?
            while process.isRunning, Date() < deadline, result == nil {
                result = parseResponse(buffer.snapshot(), now: now)
                try await Task.sleep(for: .milliseconds(50))
            }
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            output.fileHandleForReading.readabilityHandler = nil
            return result ?? parseResponse(buffer.snapshot(), now: now)
        }.value
    }

    private static func window(_ raw: Window?) -> CodexRateWindow? {
        guard let raw else { return nil }
        return CodexRateWindow(
            usedPercent: min(max(raw.usedPercent, 0), 100),
            windowMinutes: raw.windowDurationMins,
            resetsAt: raw.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private struct Envelope: Decodable {
        let id: Int?
        let result: Result?

        struct Result: Decodable {
            let rateLimits: Bucket?
            let rateLimitsByLimitId: [String: Bucket]?
        }
    }

    private struct Bucket: Decodable {
        let limitId: String?
        let limitName: String?
        let primary: Window?
        let secondary: Window?
        let planType: String?
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Double?
    }

    private final class LockedData: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ newData: Data) {
            lock.lock()
            data.append(newData)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }
}
