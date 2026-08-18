import Darwin
import Foundation
import IOKit
import IOKit.serial
import Observation

actor NotchAgentDeskSerialTransport {
    private let candidatePaths: @Sendable () -> [String]
    private let stateHandler: @Sendable (NotchAgentDeskConnectionState) -> Void
    private var loopTask: Task<Void, Never>?
    private var descriptor: Int32 = -1
    private var connectedPath: String?
    private var decoder = DeskFrameStreamDecoder()
    private var sequence: UInt32 = 0
    private var handshakeNonce: UInt32 = 0
    private var isRecognized = false
    private var isIncompatible = false
    private var acknowledgedProtocolMajor: UInt8?
    private var acknowledgedProtocolMinor: UInt8?
    private var acknowledgedFirmwareVersion: String?
    private var latestTelemetry: DeskDeviceTelemetry?
    private var pendingSnapshot: DeskSnapshot?
    private var lastHandshakeRefresh = ContinuousClock.now
    private var connectedAt = ContinuousClock.now
    private var lastHello = ContinuousClock.now
    private var candidateCooldowns: [String: ContinuousClock.Instant] = [:]

    init(
        candidatePaths: @escaping @Sendable () -> [String] = NotchAgentDeskSerialTransport.defaultCandidatePaths,
        stateHandler: @escaping @Sendable (NotchAgentDeskConnectionState) -> Void = { _ in }
    ) {
        self.candidatePaths = candidatePaths
        self.stateHandler = stateHandler
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in await self?.run() }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        disconnect()
    }

    func publish(_ snapshot: DeskSnapshot) {
        pendingSnapshot = snapshot
        guard isRecognized else { return }
        sendPendingSnapshot()
    }

    private func run() async {
        while !Task.isCancelled {
            if descriptor < 0 { connectFirstCandidate() }
            if descriptor >= 0 {
                readAvailableBytes()
                if !isRecognized, !isIncompatible,
                   connectedAt.duration(to: .now) >= .seconds(5) {
                    if let connectedPath { candidateCooldowns[connectedPath] = .now }
                    disconnect()
                } else if !isRecognized, !isIncompatible,
                          lastHello.duration(to: .now) >= .seconds(1) {
                    sendHello()
                } else if isRecognized, lastHandshakeRefresh.duration(to: .now) >= .seconds(15) {
                    // A device reset can preserve the USB descriptor while
                    // erasing its in-RAM recognized state. Re-run the nonce
                    // handshake so snapshots recover without user action.
                    handshakeNonce = UInt32.random(in: 1...UInt32.max)
                    isRecognized = false
                    connectedAt = .now
                    sendHello()
                }
            }
            try? await Task.sleep(for: .milliseconds(descriptor < 0 ? 1_000 : 100))
        }
        disconnect()
    }

    private func connectFirstCandidate() {
        let candidates = candidatePaths()
            .filter { path in
                guard let failedAt = candidateCooldowns[path] else { return true }
                return failedAt.duration(to: .now) >= .seconds(30)
            }
            .sorted()
        for path in candidates {
            let fd = path.withCString { Darwin.open($0, O_RDWR | O_NOCTTY | O_NONBLOCK) }
            guard fd >= 0 else { continue }
            guard configure(fd) else {
                Darwin.close(fd)
                continue
            }
            descriptor = fd
            connectedPath = path
            decoder = DeskFrameStreamDecoder()
            isRecognized = false
            isIncompatible = false
            latestTelemetry = nil
            connectedAt = .now
            handshakeNonce = UInt32.random(in: 1...UInt32.max)
            stateHandler(.init(phase: .handshaking, path: path))
            sendHello()
            Log.app.info("NotchAgent Desk USB candidate opened")
            return
        }
    }

    nonisolated static func defaultCandidatePaths() -> [String] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
        let matchingDictionary = matching as NSMutableDictionary
        matchingDictionary[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var paths: [String] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let vendorID = registryInteger(service, key: "idVendor"),
                  let productID = registryInteger(service, key: "idProduct"),
                  isSupportedUSBIdentity(vendorID: vendorID, productID: productID),
                  let property = IORegistryEntryCreateCFProperty(
                    service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? String else { continue }
            paths.append(property)
        }
        return Array(Set(paths)).sorted()
    }

    nonisolated static func isSupportedUSBIdentity(vendorID: Int, productID: Int) -> Bool {
        vendorID == 0x303A && productID == 0x1001
    }

    private nonisolated static func registryInteger(_ service: io_service_t, key: String) -> Int? {
        let options = IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
        guard let value = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options
        ) as? NSNumber else { return nil }
        return value.intValue
    }

    private func configure(_ fd: Int32) -> Bool {
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else { return false }
        cfmakeraw(&options)
        guard cfsetispeed(&options, speed_t(B115200)) == 0,
              cfsetospeed(&options, speed_t(B115200)) == 0
        else { return false }
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        return tcsetattr(fd, TCSANOW, &options) == 0
    }

    private func sendHello() {
        lastHello = .now
        let hello = DeskHello(
            product: NotchAgentDeskProtocol.product,
            protocolMajor: NotchAgentDeskProtocol.protocolMajor,
            protocolMinor: NotchAgentDeskProtocol.protocolMinor,
            nonce: handshakeNonce
        )
        guard let payload = encodeJSON(hello) else { return }
        send(type: .hello, payload: payload)
    }

    private func readAvailableBytes() {
        var bytes = [UInt8](repeating: 0, count: 4_096)
        while descriptor >= 0 {
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count > 0 {
                for result in decoder.append(Data(bytes.prefix(count))) {
                    if case .success(let frame) = result { handle(frame) }
                }
                continue
            }
            if count < 0, errno != EAGAIN, errno != EWOULDBLOCK { disconnect() }
            break
        }
    }

    private func handle(_ frame: DeskFrame) {
        if frame.type == .deviceTelemetry,
           isRecognized,
           let telemetry = try? decodeJSON(DeskDeviceTelemetry.self, from: frame.payload) {
            guard telemetry.firmwareVersion == acknowledgedFirmwareVersion else {
                Log.app.error("NotchAgent Desk handshake and telemetry firmware versions disagree")
                if let connectedPath { candidateCooldowns[connectedPath] = .now }
                disconnect()
                return
            }
            latestTelemetry = telemetry
            stateHandler(.init(
                phase: .connected,
                path: connectedPath,
                firmwareVersion: telemetry.firmwareVersion,
                protocolMajor: acknowledgedProtocolMajor,
                protocolMinor: acknowledgedProtocolMinor,
                telemetry: telemetry
            ))
            return
        }
        guard frame.type == .helloAcknowledgement,
              let acknowledgement = try? decodeJSON(DeskHelloAcknowledgement.self, from: frame.payload),
              acknowledgement.product == NotchAgentDeskProtocol.product,
              acknowledgement.nonce == handshakeNonce
        else { return }
        guard acknowledgement.protocolMajor == NotchAgentDeskProtocol.protocolMajor else {
            isIncompatible = true
            stateHandler(.init(
                phase: .incompatible,
                path: connectedPath,
                firmwareVersion: acknowledgement.firmwareVersion,
                protocolMajor: acknowledgement.protocolMajor,
                protocolMinor: acknowledgement.protocolMinor
            ))
            return
        }
        guard let firmwareVersion = acknowledgement.firmwareVersion,
              firmwareVersion.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil else {
            isIncompatible = true
            stateHandler(.init(
                phase: .incompatible,
                path: connectedPath,
                protocolMajor: acknowledgement.protocolMajor,
                protocolMinor: acknowledgement.protocolMinor
            ))
            return
        }
        isRecognized = true
        isIncompatible = false
        acknowledgedProtocolMajor = acknowledgement.protocolMajor
        acknowledgedProtocolMinor = acknowledgement.protocolMinor
        acknowledgedFirmwareVersion = firmwareVersion
        lastHandshakeRefresh = .now
        candidateCooldowns[connectedPath ?? ""] = nil
        Log.app.info("NotchAgent Desk recognized")
        stateHandler(.init(
            phase: .connected,
            path: connectedPath,
            firmwareVersion: acknowledgement.firmwareVersion,
            protocolMajor: acknowledgement.protocolMajor,
            protocolMinor: acknowledgement.protocolMinor,
            telemetry: latestTelemetry
        ))
        sendPendingSnapshot()
    }

    private func sendPendingSnapshot() {
        guard let snapshot = pendingSnapshot, let payload = encodeJSON(snapshot) else { return }
        guard payload.count <= NotchAgentDeskProtocol.maximumPayloadBytes else {
            Log.app.error("NotchAgent Desk snapshot exceeds protocol limit")
            return
        }
        send(type: .snapshot, payload: payload)
    }

    private func send(type: NotchAgentDeskProtocol.FrameType, payload: Data) {
        guard descriptor >= 0 else { return }
        sequence &+= 1
        guard let data = try? DeskFrameCodec.encode(.init(type: type, sequence: sequence, payload: payload)) else { return }
        let result = data.withUnsafeBytes { rawBuffer -> Int in
            guard let base = rawBuffer.baseAddress else { return 0 }
            var written = 0
            while written < rawBuffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: written), rawBuffer.count - written)
                if count > 0 { written += count; continue }
                if count < 0, errno == EINTR { continue }
                if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    var writable = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                    let ready = Darwin.poll(&writable, 1, 500)
                    if ready > 0 { continue }
                    if ready < 0, errno == EINTR { continue }
                }
                return -1
            }
            return written
        }
        if result < 0 { disconnect() }
    }

    private func disconnect() {
        if descriptor >= 0 { Darwin.close(descriptor) }
        descriptor = -1
        connectedPath = nil
        isRecognized = false
        isIncompatible = false
        acknowledgedProtocolMajor = nil
        acknowledgedProtocolMinor = nil
        acknowledgedFirmwareVersion = nil
        latestTelemetry = nil
        decoder = DeskFrameStreamDecoder()
        stateHandler(.searching)
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try? encoder.encode(value)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

@Observable
@MainActor
final class NotchAgentDeskCoordinator {
    private let store: UsageStore
    private let soakRecorder: NotchAgentDeskSoakRecorder?
    private(set) var connectionState = NotchAgentDeskConnectionState.disabled
    private(set) var updateState = NotchAgentDeskUpdateState.unavailable
    @ObservationIgnored private var transport: NotchAgentDeskSerialTransport! = nil
    private var publishTask: Task<Void, Never>?
    /// Serializes rapid enable/disable changes so an older stop cannot win
    /// after a newer start.
    private var lifecycleTask: Task<Void, Never>?
    private var isStarted = false
    private var isMirroringEnabled = false
    @ObservationIgnored var onConnectionPhaseChange: ((NotchAgentDeskConnectionState.Phase) -> Void)?

    init(store: UsageStore, soakRecorder: NotchAgentDeskSoakRecorder? = .fromEnvironment()) {
        self.store = store
        self.soakRecorder = soakRecorder
        transport = NotchAgentDeskSerialTransport(stateHandler: { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                let previousPhase = self.connectionState.phase
                self.connectionState = state
                self.soakRecorder?.record(state)
                if previousPhase != state.phase {
                    self.onConnectionPhaseChange?(state.phase)
                }
            }
        })
        if let package = try? NotchAgentDeskFirmwareUpdater.bundledPackage() {
            updateState = .ready(version: package.manifest.firmwareVersion)
        }
    }

    func start(mirroringEnabled: Bool) {
        if isStarted {
            setMirroringEnabled(mirroringEnabled)
            return
        }
        isStarted = true
        isMirroringEnabled = mirroringEnabled
        connectionState = .searching
        soakRecorder?.record(.searching)
        updateStoreObservation()
        let previous = lifecycleTask
        let transport = transport!
        lifecycleTask = Task { [transport] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await transport.start()
        }
        if mirroringEnabled { schedulePublish() }
        else { publishPrivacyBlank() }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        isMirroringEnabled = false
        connectionState = .disabled
        soakRecorder?.record(.disabled)
        store.onDeskStateChange = nil
        publishTask?.cancel()
        publishTask = nil
        let previous = lifecycleTask
        let transport = transport!
        lifecycleTask = Task { [transport] in
            await previous?.value
            await transport.stop()
        }
    }

    func settingsDidChange() {
        guard isStarted, isMirroringEnabled else { return }
        schedulePublish()
    }

    func setMirroringEnabled(_ enabled: Bool) {
        guard isStarted else {
            start(mirroringEnabled: enabled)
            return
        }
        guard isMirroringEnabled != enabled else { return }
        isMirroringEnabled = enabled
        updateStoreObservation()
        publishTask?.cancel()
        publishTask = nil
        if enabled {
            schedulePublish()
        } else {
            publishPrivacyBlank()
        }
    }

    func installBundledFirmware() {
        if case .updating = updateState { return }
        guard let path = connectionState.path else {
            updateState = .failed(message: "Connect NotchAgent Desk before updating.")
            return
        }
        let package: DeskFirmwarePackage
        do {
            package = try NotchAgentDeskFirmwareUpdater.bundledPackage()
        } catch {
            updateState = .failed(message: error.localizedDescription)
            return
        }
        updateState = .updating
        let previous = lifecycleTask
        let transport = transport!
        lifecycleTask = Task { [weak self, transport] in
            await previous?.value
            await transport.stop()
            guard let self else { return }
            self.connectionState = .searching
            do {
                try await NotchAgentDeskFirmwareUpdater.flash(package: package, port: path)
                await transport.start()
                try await self.waitForInstalledFirmware(package.manifest.firmwareVersion)
                self.updateState = .succeeded(version: package.manifest.firmwareVersion)
                self.schedulePublish()
            } catch {
                await transport.start()
                self.updateState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func waitForInstalledFirmware(_ expectedVersion: String) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        while clock.now < deadline {
            switch DeskFirmwareVerification.evaluate(
                connectionState,
                expectedVersion: expectedVersion
            ) {
            case .installed:
                return
            case .versionMismatch:
                throw DeskFirmwareUpdateError.verificationFailed
            case .waiting:
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw DeskFirmwareUpdateError.verificationFailed
    }

    private func schedulePublish() {
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self, self.isMirroringEnabled else { return }
            let snapshot = DeskSnapshotFactory.make(from: self.store)
            await self.transport.publish(snapshot)
        }
    }

    private func updateStoreObservation() {
        store.onDeskStateChange = isMirroringEnabled ? { [weak self] in self?.schedulePublish() } : nil
    }

    private func publishPrivacyBlank() {
        let blank = DeskSnapshot(
            product: NotchAgentDeskProtocol.product,
            protocolMajor: NotchAgentDeskProtocol.protocolMajor,
            protocolMinor: NotchAgentDeskProtocol.protocolMinor,
            generatedAt: Date(), overallAttention: .normal, isPaused: true,
            providers: [], burnHistory: [], rhythm: [],
            currentHour: Calendar.current.component(.hour, from: Date()), currentHourElapsedFraction: 0,
            models: [],
            alertThresholds: ThresholdAlerts.defaultLevels, runnerEnabled: false,
            ambientRecommendation: .init(
                page: .now, reason: "Usage mirroring disabled", severity: .normal
            )
        )
        Task { await transport.publish(blank) }
    }
}
