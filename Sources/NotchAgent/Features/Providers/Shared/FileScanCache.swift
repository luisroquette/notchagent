import Foundation

/// Per-file parse cache keyed by (mtime, size). Providers scan directories every
/// refresh; only files that actually changed get re-parsed. In-memory only —
/// a cold launch re-parses the lookback window once, which is acceptable.
actor FileScanCache<Value: Sendable> {
    private struct Entry {
        let stamp: FileStamp
        let value: Value
    }

    private var entries: [String: Entry] = [:]

    /// Returns the cached value when the file is unchanged, otherwise runs
    /// `parse` and stores its result.
    func value(for url: URL, parse: @Sendable (URL) throws -> Value) rethrows -> Value? {
        guard let stamp = FileStamp(url: url) else { return nil }
        let key = url.path
        if let entry = entries[key], entry.stamp == stamp {
            return entry.value
        }
        let value = try parse(url)
        entries[key] = Entry(stamp: stamp, value: value)
        return value
    }

    func removeAll() {
        entries.removeAll()
    }

    /// Drops entries for files no longer in the scan set.
    func prune(keeping paths: Set<String>) {
        entries = entries.filter { paths.contains($0.key) }
    }
}
