import Foundation

/// Append-only log file for field diagnosis. The unified os_log does NOT
/// persist by default — diagnosing the probe's silent failure cost hours
/// precisely because `log stream` saw nothing. Critical paths mirror
/// their logs here so the next field issue reads in minutes from
/// `~/Library/Application Support/NotchAgent/app.log`. Capped at 512KB
/// (truncated in place) so it never grows unbounded.
enum LogFile {
    static let maxBytes = 512 * 1024

    static var url: URL {
        AppPaths.appSupport.appendingPathComponent("app.log")
    }

    private static let queue = DispatchQueue(label: "br.com.lfrprojects.notchagent.logfile")

    static func write(_ category: String, _ message: String) {
        queue.async {
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(stamp) [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            do {
                let handle: FileHandle
                if FileManager.default.fileExists(atPath: url.path) {
                    handle = try FileHandle(forWritingTo: url)
                } else {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    handle = try FileHandle(forWritingTo: url)
                }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
                capIfNeeded()
            } catch {
                // Logging must never crash the app.
            }
        }
    }

    private static func capIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size > maxBytes else { return }
        // Keep the LAST half — the newest diagnostics.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let data = try? handle.readToEnd(), data.count > maxBytes / 2 else { return }
        let tail = data.suffix(maxBytes / 2)
        try? tail.write(to: url)
    }
}
