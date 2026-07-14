import Foundation

/// Streaming reader for JSONL files. Keeps memory flat regardless of file size
/// and tolerates a truncated final line (common while a CLI is still writing).
enum JSONLReader {
    /// Calls `body` once per complete non-empty line, starting at `offset`.
    /// Returns the offset just past the last complete line consumed — a
    /// trailing line with no newline yet (still being written) is NOT
    /// consumed, so incremental callers re-read it once it completes.
    @discardableResult
    static func forEachLine(
        at url: URL,
        startingAt offset: UInt64 = 0,
        _ body: (Data, _ stop: inout Bool) throws -> Void
    ) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if offset > 0 {
            try handle.seek(toOffset: offset)
        }

        var consumed = offset
        var buffer = Data()
        var stop = false
        while !stop {
            guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            buffer.append(chunk)

            var start = buffer.startIndex
            while !stop, let newline = buffer[start...].firstIndex(of: 0x0A) {
                if newline > start {
                    try body(Data(buffer[start..<newline]), &stop)
                }
                consumed += UInt64(newline - start) + 1
                start = buffer.index(after: newline)
            }
            buffer.removeSubrange(buffer.startIndex..<start)
        }
        return consumed
    }

    /// Last `maxBytes` of the file, aligned to the first full line inside the window.
    static func tailLines(at url: URL, maxBytes: Int) throws -> [Data] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try handle.seek(toOffset: offset)
        guard let data = try handle.readToEnd(), !data.isEmpty else { return [] }

        var lines: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            let newline = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            if newline > start {
                lines.append(Data(data[start..<newline]))
            }
            start = newline < data.endIndex ? data.index(after: newline) : data.endIndex
        }
        // The first line is likely cut in half when we started mid-file.
        if offset > 0, !lines.isEmpty {
            lines.removeFirst()
        }
        return lines
    }
}
