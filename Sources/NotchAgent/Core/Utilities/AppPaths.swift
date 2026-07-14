import Foundation

enum AppPaths {
    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// ~/Library/Application Support/NotchAgent (created on first access).
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotchAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

struct FileStamp: Equatable, Sendable {
    let modified: Date
    let size: Int

    init?(url: URL) {
        // FileManager instead of URL.resourceValues: NSURL caches resource
        // values per instance, which would freeze the stamp of the live,
        // constantly-growing transcript within a refresh cycle.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.intValue
        else { return nil }
        self.modified = modified
        self.size = size
    }
}

/// Recursively lists files with `ext`, modified after `cutoff`, newest first, capped.
func recentFiles(under root: URL, ext: String, modifiedAfter cutoff: Date, limit: Int = 500) -> [URL] {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
    ) else { return [] }

    var result: [(URL, Date)] = []
    for case let url as URL in enumerator {
        guard url.pathExtension == ext,
              let values = try? url.resourceValues(forKeys: Set(keys)),
              values.isRegularFile == true,
              let modified = values.contentModificationDate,
              modified >= cutoff
        else { continue }
        result.append((url, modified))
    }
    return result
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
}
