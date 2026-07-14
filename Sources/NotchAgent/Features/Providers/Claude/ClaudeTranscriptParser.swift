import Foundation

/// Aggregated stats for one Claude Code transcript file (`~/.claude/projects/<slug>/<session>.jsonl`).
/// Hour buckets keep memory flat and are all the session-block math needs.
struct ClaudeFileStat: Sendable {
    struct HourStat: Sendable {
        var tokens: TokenUsage = .zero
        var costUSD: Double = 0
        var messages: Int = 0
    }

    struct ModelStat: Sendable {
        var tokens: TokenUsage = .zero
        var costUSD: Double = 0
    }

    var hours: [Date: HourStat] = [:]
    var byModel: [String: ModelStat] = [:]
    var lastActivity: Date?
    var lastModel: String?
    var usageLineCount: Int = 0
    /// Dedup keys survive incremental re-parses of the same file.
    var seenKeys: Set<String> = []
}

enum ClaudeTranscriptParser {
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let inputTokens: Int?
                let outputTokens: Int?
                let cacheCreationInputTokens: Int?
                let cacheReadInputTokens: Int?
            }
            let id: String?
            let model: String?
            let usage: Usage?
        }
        let type: String?
        let timestamp: String?
        let requestId: String?
        let message: Message?
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let assistantMarker = Data("\"assistant\"".utf8)

    /// Byte-level pre-filter: transcripts carry multi-megabyte lines (base64
    /// images, tool dumps) that can never be usage records. memchr-speed scans
    /// skip them before the expensive JSONDecoder ever runs — this is what
    /// keeps a 100 MB live transcript parseable every refresh.
    static func quickMatch(_ line: Data) -> Bool {
        line.range(of: usageMarker) != nil && line.range(of: assistantMarker) != nil
    }

    /// Tolerant: malformed lines are skipped, only assistant lines with usage count.
    /// Deduplicates by requestId/message.id (retries re-log usage).
    /// Incremental: pass `from`/`into` to parse only bytes appended since the
    /// last scan; returns the stat plus the consumed byte offset.
    static func parseFile(
        at url: URL,
        from offset: UInt64 = 0,
        into base: ClaudeFileStat? = nil
    ) throws -> (stat: ClaudeFileStat, consumed: UInt64) {
        var stat = base ?? ClaudeFileStat()

        let consumed = try JSONLReader.forEachLine(at: url, startingAt: offset) { data, _ in
            guard quickMatch(data),
                  let line = try? decoder.decode(Line.self, from: data),
                  line.type == "assistant",
                  let usage = line.message?.usage,
                  let timestampString = line.timestamp,
                  let timestamp = Timestamps.parseISO8601(timestampString)
            else { return }

            if let key = line.requestId ?? line.message?.id {
                guard stat.seenKeys.insert(key).inserted else { return }
            }

            let model = line.message?.model ?? "claude"
            let tokens = TokenUsage(
                input: usage.inputTokens ?? 0,
                output: usage.outputTokens ?? 0,
                cacheWrite: usage.cacheCreationInputTokens ?? 0,
                cacheRead: usage.cacheReadInputTokens ?? 0
            )

            let cost = PricingTable.costUSD(model: model, usage: tokens)
            let hour = timestamp.flooredToHour
            var bucket = stat.hours[hour] ?? .init()
            bucket.tokens += tokens
            bucket.costUSD += cost
            bucket.messages += 1
            stat.hours[hour] = bucket

            var modelStat = stat.byModel[model] ?? .init()
            modelStat.tokens += tokens
            modelStat.costUSD += cost
            stat.byModel[model] = modelStat

            if stat.lastActivity.map({ timestamp > $0 }) ?? true {
                stat.lastActivity = timestamp
                stat.lastModel = model
            }
            stat.usageLineCount += 1
        }
        return (stat, consumed)
    }
}

/// Incremental per-file cache: unchanged files hit the cache, grown files
/// parse only the appended bytes, truncated/rotated files re-parse fully.
/// Without this, the actively-written transcript (100+ MB during long
/// sessions) would be re-parsed whole on every refresh tick.
actor ClaudeScanCache {
    private struct Entry {
        var stamp: FileStamp
        var offset: UInt64
        var stat: ClaudeFileStat
    }

    private var entries: [String: Entry] = [:]

    func stat(for url: URL) throws -> ClaudeFileStat? {
        guard let stamp = FileStamp(url: url) else { return nil }
        let key = url.path

        if let entry = entries[key] {
            if entry.stamp == stamp {
                return entry.stat
            }
            if UInt64(stamp.size) >= entry.offset {
                let (stat, consumed) = try ClaudeTranscriptParser.parseFile(
                    at: url, from: entry.offset, into: entry.stat
                )
                entries[key] = Entry(stamp: stamp, offset: consumed, stat: stat)
                return stat
            }
            // File shrank — rotated or rewritten. Fall through to a full parse.
        }
        let (stat, consumed) = try ClaudeTranscriptParser.parseFile(at: url)
        entries[key] = Entry(stamp: stamp, offset: consumed, stat: stat)
        return stat
    }

    /// Drops entries for files no longer in the scan set (deleted or aged out
    /// of the lookback), bounding memory for long-running sessions.
    func prune(keeping paths: Set<String>) {
        entries = entries.filter { paths.contains($0.key) }
    }
}

/// Claude Plans meter usage in rolling ~5h session blocks. This reproduces the
/// commonly used heuristic (same as ccusage): a block starts at the floored hour
/// of the first activity after the previous block ended, and lasts 5 hours.
enum SessionBlocks {
    static let blockLength: TimeInterval = 5 * 3600

    /// Returns the active block containing `now`, or nil when idle.
    static func currentBlock(activityHours: [Date], now: Date) -> (start: Date, end: Date)? {
        var blockStart: Date?
        var blockEnd = Date.distantPast

        for hour in activityHours.sorted() {
            if blockStart == nil || hour >= blockEnd {
                blockStart = hour
                blockEnd = hour.addingTimeInterval(blockLength)
            }
        }
        guard let start = blockStart, now >= start, now < blockEnd else { return nil }
        return (start, blockEnd)
    }
}
