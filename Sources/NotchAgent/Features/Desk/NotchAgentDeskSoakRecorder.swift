import Foundation

struct DeskSoakRecord: Codable, Sendable, Equatable {
    var capturedAt: Date
    var elapsedMilliseconds: Int64
    var phase: NotchAgentDeskConnectionState.Phase
    var firmwareVersion: String?
    var protocolMajor: UInt8?
    var protocolMinor: UInt8?
    var telemetry: DeskDeviceTelemetry?
    var reliabilityFailures: [String]
}

@MainActor
final class NotchAgentDeskSoakRecorder {
    private let startedAt = ContinuousClock.now
    private let encoder: JSONEncoder
    private var handle: FileHandle?
    private var touchContinuityMonitor = DeskTouchContinuityMonitor()

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NotchAgentDeskSoakRecorder? {
        guard let path = environment["NOTCHAGENT_DESK_SOAK_REPORT"], path.hasPrefix("/") else { return nil }
        return try? NotchAgentDeskSoakRecorder(reportURL: URL(fileURLWithPath: path))
    }

    init(reportURL: URL) throws {
        let directory = reportURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: reportURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: reportURL)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func record(_ state: NotchAgentDeskConnectionState) {
        guard let handle else { return }
        let duration = startedAt.duration(to: .now).components
        let elapsedMilliseconds = duration.seconds * 1_000
            + duration.attoseconds / 1_000_000_000_000_000
        var failures = state.telemetry.map { DeskReliabilityAssessment.assess($0).failures } ?? []
        if let telemetry = state.telemetry,
           let touchFailure = touchContinuityMonitor.assess(telemetry) {
            failures.append(touchFailure)
        }
        let record = DeskSoakRecord(
            capturedAt: Date(),
            elapsedMilliseconds: elapsedMilliseconds,
            phase: state.phase,
            firmwareVersion: state.firmwareVersion,
            protocolMajor: state.protocolMajor,
            protocolMinor: state.protocolMinor,
            telemetry: state.telemetry,
            reliabilityFailures: failures
        )
        do {
            var line = try encoder.encode(record)
            line.append(0x0A)
            try handle.write(contentsOf: line)
            try handle.synchronize()
        } catch {
            Log.app.error("Desk soak report write failed")
            close()
        }
    }

    func close() {
        try? handle?.close()
        handle = nil
    }

    deinit {
        try? handle?.close()
    }
}
