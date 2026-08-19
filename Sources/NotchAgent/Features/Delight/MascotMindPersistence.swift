import Foundation

/// JSON persistence for the mascot's inner life. A corrupt or missing file
/// is a fresh start — the mascot is never blocked by a bad save.
public struct MascotMindPersistence {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("NotchAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("mascot-mind.json")
    }

    public func load() -> MascotMindState {
        guard let data = try? Data(contentsOf: fileURL) else { return MascotMindState() }
        let decoder = JSONDecoder()
        // Dates come from state snapshots; tolerate both ms and s precision.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(Double.self)
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        guard let state = try? decoder.decode(MascotMindState.self, from: data) else {
            return MascotMindState()
        }
        return state
    }

    public func save(_ state: MascotMindState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
