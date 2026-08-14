import Darwin
import CryptoKit
import Foundation
import XCTest
@testable import NotchAgent

final class NotchAgentDeskTests: XCTestCase {
    func testCodexOnboardingStatesAreExplicitAndOrdered() {
        XCTAssertEqual(CodexOnboardingStatus.classify(
            cliInstalled: false, authenticated: false, hasSession: false
        ), .notInstalled)
        XCTAssertEqual(CodexOnboardingStatus.classify(
            cliInstalled: true, authenticated: false, hasSession: false
        ), .notAuthenticated)
        XCTAssertEqual(CodexOnboardingStatus.classify(
            cliInstalled: true, authenticated: true, hasSession: false
        ), .noSession)
        XCTAssertEqual(CodexOnboardingStatus.classify(
            cliInstalled: true, authenticated: true, hasSession: true
        ), .ready)
        XCTAssertEqual(CodexOnboardingStatus.notInstalled.action, .openInstallGuide)
        XCTAssertEqual(CodexOnboardingStatus.notAuthenticated.action, .authenticate)
        XCTAssertEqual(CodexOnboardingStatus.noSession.action, .createFirstSession)
        XCTAssertNil(CodexOnboardingStatus.ready.action)
    }

    func testCodexOnboardingUsesSeparateSafeCommandsForLoginAndFirstSession() {
        let executable = URL(fileURLWithPath: "/tmp/Codex Folder/codex")
        XCTAssertEqual(
            CodexOnboardingInspector.loginInvocation(executable: executable),
            CodexProcessInvocation(executableURL: executable, arguments: ["login"])
        )
        XCTAssertEqual(
            CodexOnboardingInspector.firstSessionInvocation(executable: executable),
            CodexProcessInvocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-a", "Terminal", "/tmp/Codex Folder/codex"]
            )
        )
    }

    func testCodexOnboardingRequiresAnActualRolloutFile() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("NotchAgent-CodexOnboarding-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertFalse(CodexOnboardingInspector.hasSession(at: root))

        let nested = root.appendingPathComponent("2026/08/14", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("unrelated.jsonl"))
        XCTAssertFalse(CodexOnboardingInspector.hasSession(at: root))

        try Data().write(to: nested.appendingPathComponent("rollout-empty.jsonl"))
        XCTAssertFalse(CodexOnboardingInspector.hasSession(at: root))

        let fixture = Bundle.module.url(
            forResource: "codex-rollout",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )!
        let rollout = nested.appendingPathComponent("rollout-test.jsonl")
        try fileManager.copyItem(
            at: fixture,
            to: rollout
        )
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: rollout.path)
        XCTAssertTrue(CodexOnboardingInspector.hasSession(at: root))
    }

    func testCodexOnboardingLiveLoginWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NOTCHAGENT_CODEX_LOGIN_E2E"] == "1" else {
            throw XCTSkip("Set NOTCHAGENT_CODEX_LOGIN_E2E=1 for the local login test")
        }
        let status = await CodexOnboardingInspector.inspect()
        XCTAssertEqual(status, .ready)
    }

    func testDeskDiscoveryAcceptsOnlyTheBeta1USBIdentity() {
        XCTAssertTrue(NotchAgentDeskSerialTransport.isSupportedUSBIdentity(vendorID: 0x303A, productID: 0x1001))
        XCTAssertFalse(NotchAgentDeskSerialTransport.isSupportedUSBIdentity(vendorID: 0x303A, productID: 0x0002))
        XCTAssertFalse(NotchAgentDeskSerialTransport.isSupportedUSBIdentity(vendorID: 0x1234, productID: 0x1001))
    }

    func testDeskDiscoveryEnumerationIsSafeAndDeterministic() {
        let paths = NotchAgentDeskSerialTransport.defaultCandidatePaths()
        XCTAssertEqual(paths, paths.sorted())
        XCTAssertEqual(Set(paths).count, paths.count)
        XCTAssertTrue(paths.allSatisfy { $0.hasPrefix("/dev/cu.usbmodem") })
    }
    func testDeskUsageMirroringIsOptInByDefault() {
        XCTAssertFalse(AppSettings().notchAgentDeskEnabled)
        XCTAssertFalse(AppSettings().claudeQuotaProbeEnabled)
    }

    func testDeskSetupRequiresConnectionProviderAndConsent() {
        var status = NotchAgentDeskSetupStatus(
            connectionPhase: .searching,
            mirroringEnabled: false,
            claudeInstallation: .notInstalled,
            codexInstallation: .notInstalled,
            claudeHealth: nil,
            codexHealth: nil,
            claudeRefreshState: .idle,
            codexRefreshState: .idle
        )
        XCTAssertFalse(status.isReady)
        XCTAssertFalse(status.canEnableMirroring)
        XCTAssertEqual(status.desk, .waiting)
        XCTAssertEqual(status.mirroring, .actionRequired)

        status = NotchAgentDeskSetupStatus(
            connectionPhase: .connected,
            mirroringEnabled: true,
            claudeInstallation: .notInstalled,
            codexInstallation: .installed(dataPath: "/private/local-only"),
            claudeHealth: nil,
            codexHealth: .ok,
            claudeRefreshState: .idle,
            codexRefreshState: .success(Date())
        )
        XCTAssertTrue(status.isReady)
        XCTAssertTrue(status.canEnableMirroring)
        XCTAssertTrue(status.hasLocalProvider)
        XCTAssertEqual(status.codex, .ready)
    }

    func testDeskSetupFlagsIncompatibleFirmwareAsActionRequired() {
        let status = NotchAgentDeskSetupStatus(
            connectionPhase: .incompatible,
            mirroringEnabled: false,
            claudeInstallation: .installed(dataPath: "/private/local-only"),
            codexInstallation: .notInstalled,
            claudeHealth: .ok,
            codexHealth: nil,
            claudeRefreshState: .success(Date()),
            codexRefreshState: .idle
        )
        XCTAssertEqual(status.desk, .actionRequired)
        XCTAssertFalse(status.isReady)
    }

    func testDeskSetupDoesNotTreatAnEmptyInstallationAsReady() {
        let status = NotchAgentDeskSetupStatus(
            connectionPhase: .connected,
            mirroringEnabled: false,
            claudeInstallation: .installed(dataPath: "/private/local-only"),
            codexInstallation: .notInstalled,
            claudeHealth: .noData,
            codexHealth: nil,
            claudeRefreshState: .success(Date()),
            codexRefreshState: .idle
        )
        XCTAssertEqual(status.claude, .waiting)
        XCTAssertFalse(status.hasLocalProvider)
        XCTAssertFalse(status.canEnableMirroring)
    }

    func testDeskSetupRejectsPersistedSnapshotBeforeCurrentRefresh() {
        let status = NotchAgentDeskSetupStatus(
            connectionPhase: .connected,
            mirroringEnabled: false,
            claudeInstallation: .installed(dataPath: "/private/local-only"),
            codexInstallation: .notInstalled,
            claudeHealth: .ok,
            codexHealth: nil,
            claudeRefreshState: .idle,
            codexRefreshState: .idle
        )
        XCTAssertEqual(status.claude, .waiting)
        XCTAssertFalse(status.canEnableMirroring)
    }

    func testDeskSetupSurfacesProviderReadFailure() {
        let status = NotchAgentDeskSetupStatus(
            connectionPhase: .connected,
            mirroringEnabled: false,
            claudeInstallation: .installed(dataPath: "/private/local-only"),
            codexInstallation: .notInstalled,
            claudeHealth: .ok,
            codexHealth: nil,
            claudeRefreshState: .failure(Date(), "private raw error"),
            codexRefreshState: .idle
        )
        XCTAssertEqual(status.claude, .actionRequired)
        XCTAssertTrue(status.hasProviderError)
        XCTAssertFalse(status.canEnableMirroring)
    }

    @MainActor
    func testBurnHistoryUsesPrimaryProviderAndBoundsValues() {
        let suite = "NotchAgentDeskTests.Burn.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(preferences: PreferencesStore(defaults: defaults))
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            capturedAt: now.addingTimeInterval(-60),
            health: .ok,
            session: SessionUsage(usedPercent: 25),
            lastActivityAt: now
        ))
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            capturedAt: now,
            health: .ok,
            session: SessionUsage(usedPercent: 35),
            lastActivityAt: now
        ))

        let snapshot = DeskSnapshotFactory.make(from: store, now: now)
        XCTAssertEqual(snapshot.providers.first?.id, .claudeCode)
        XCTAssertEqual(snapshot.burnHistory.map(\.usedPercent), [25, 35])
        XCTAssertEqual(snapshot.burnHistory.map(\.ageSeconds), [60, 0])
    }

    @MainActor
    func testSnapshotCarriesPauseRunnerAndAlertConfiguration() {
        let suite = "NotchAgentDeskTests.Configuration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.settings.runnerEnabled = false
        preferences.settings.quotaAlertThresholdPercents = [5, 25, 75, 100, 50]
        let store = UsageStore(preferences: preferences)
        store.isPaused = true

        let snapshot = DeskSnapshotFactory.make(from: store)
        XCTAssertTrue(snapshot.isPaused)
        XCTAssertFalse(snapshot.runnerEnabled)
        XCTAssertEqual(snapshot.alertThresholds, [100, 75, 50, 25, 5])
    }

    @MainActor
    func testWeeklyGaugeNeverReusesSessionBurnHistory() {
        let suite = "NotchAgentDeskTests.WeeklyBurn.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(preferences: PreferencesStore(defaults: defaults))
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            capturedAt: now.addingTimeInterval(-600),
            health: .ok,
            session: SessionUsage(usedPercent: 10)
        ))
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            capturedAt: now,
            health: .ok,
            session: SessionUsage(usedPercent: 20)
        ))
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            capturedAt: now.addingTimeInterval(1),
            health: .ok,
            weekly: WeeklyUsage(usedPercent: 40)
        ))

        let snapshot = DeskSnapshotFactory.make(from: store, now: now.addingTimeInterval(1))
        XCTAssertEqual(snapshot.providers.first?.window, .weekly)
        XCTAssertNil(snapshot.providers.first?.burnPercentPerHour)
        XCTAssertNil(snapshot.providers.first?.exhaustsAt)
        XCTAssertTrue(snapshot.burnHistory.isEmpty)
    }

    func testFrameRoundTripHandlesZerosAndBoundaries() throws {
        let payload = Data([0, 1, 2, 0, 255, 0, 3])
        let encoded = try DeskFrameCodec.encode(.init(type: .snapshot, sequence: 42, payload: payload))
        XCTAssertEqual(encoded.last, 0)
        let decoded = try DeskFrameCodec.decodePacket(encoded.dropLast())
        XCTAssertEqual(decoded, DeskFrame(type: .snapshot, sequence: 42, payload: payload))
    }

    func testCorruptedFrameIsRejected() throws {
        var encoded = Array(try DeskFrameCodec.encode(.init(type: .heartbeat, sequence: 7, payload: Data("ok".utf8))))
        encoded[encoded.count / 2] ^= 0x55
        XCTAssertThrowsError(try DeskFrameCodec.decodePacket(Data(encoded.dropLast())))
    }

    func testStreamDecoderResynchronizesAfterBadPacket() throws {
        let good = try DeskFrameCodec.encode(.init(type: .heartbeat, sequence: 8, payload: Data()))
        var decoder = DeskFrameStreamDecoder()
        let results = decoder.append(Data([1, 2, 0]) + good)
        XCTAssertEqual(results.count, 2)
        guard case .success(let frame) = results[1] else { return XCTFail("expected resynchronized frame") }
        XCTAssertEqual(frame.sequence, 8)
    }

    func testSerialTransportWaitsForHandshakeThenPublishes() async throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 1_024)
        XCTAssertEqual(openpty(&master, &slave, &name, nil, nil), 0)
        guard master >= 0, slave >= 0 else { return XCTFail("openpty failed") }
        defer {
            Darwin.close(master)
            Darwin.close(slave)
        }
        let pathBytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let path = String(decoding: pathBytes, as: UTF8.self)
        let flags = fcntl(master, F_GETFL)
        XCTAssertEqual(fcntl(master, F_SETFL, flags | O_NONBLOCK), 0)

        let stateRecorder = DeskConnectionStateRecorder()
        let transport = NotchAgentDeskSerialTransport(
            candidatePaths: { [path] in [path] },
            stateHandler: { stateRecorder.append($0) }
        )
        let snapshot = DeskSnapshot(
            product: NotchAgentDeskProtocol.product,
            protocolMajor: 1,
            protocolMinor: 0,
            generatedAt: Date(timeIntervalSince1970: 1_900_000_000),
            overallAttention: .normal,
            isPaused: false,
            providers: [],
            burnHistory: [],
            rhythm: [],
            models: []
        )
        await transport.publish(snapshot)
        await transport.start()

        let hello = try await readFrame(from: master, timeout: .seconds(3))
        XCTAssertEqual(hello.type, .hello)
        XCTAssertNil(tryReadFrame(from: master))

        let helloDecoder = JSONDecoder()
        var wrongHello = try helloDecoder.decode(DeskHello.self, from: hello.payload)
        let expectedNonce = wrongHello.nonce
        wrongHello.nonce &+= 1
        let wrongAcknowledgement = try DeskFrameCodec.encode(.init(
            type: .helloAcknowledgement,
            sequence: 1,
            payload: try JSONEncoder().encode(wrongHello)
        ))
        try writeAll(wrongAcknowledgement, to: master)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(tryReadFrame(from: master))

        let acknowledgedHello = DeskHelloAcknowledgement(
            product: wrongHello.product,
            protocolMajor: wrongHello.protocolMajor,
            protocolMinor: 1,
            nonce: expectedNonce,
            firmwareVersion: "0.6.0"
        )
        let acknowledgement = try DeskFrameCodec.encode(.init(
            type: .helloAcknowledgement,
            sequence: 2,
            payload: try JSONEncoder().encode(acknowledgedHello)
        ))
        try writeAll(acknowledgement, to: master)
        let published = try await readFrame(from: master, timeout: .seconds(3))
        XCTAssertEqual(published.type, .snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        XCTAssertEqual(try decoder.decode(DeskSnapshot.self, from: published.payload), snapshot)
        XCTAssertEqual(stateRecorder.last?.phase, .connected)
        XCTAssertEqual(stateRecorder.last?.firmwareVersion, "0.6.0")
        XCTAssertEqual(stateRecorder.last?.protocolMinor, 1)

        let telemetry = DeskDeviceTelemetry(
            firmwareVersion: "0.6.0",
            uptimeSeconds: 42,
            freeHeapBytes: 200_000,
            minimumFreeHeapBytes: 180_000,
            framesPerSecond: 18.5,
            resetReason: "power_on",
            invalidFrameCount: 0,
            handshakeCount: 1,
            touchCount: 3,
            touchInterruptCount: 4,
            touchReadErrorCount: 0,
            lastTouchLatencyMs: 4.2,
            maximumTouchLatencyMs: 8.4
        )
        try writeAll(try DeskFrameCodec.encode(.init(
            type: .deviceTelemetry,
            sequence: 3,
            payload: try JSONEncoder().encode(telemetry)
        )), to: master)
        let telemetryDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while stateRecorder.last?.telemetry != telemetry,
              ContinuousClock.now < telemetryDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(stateRecorder.last?.telemetry, telemetry)

        var mismatchedTelemetry = telemetry
        mismatchedTelemetry.firmwareVersion = "0.6.1"
        try writeAll(try DeskFrameCodec.encode(.init(
            type: .deviceTelemetry,
            sequence: 4,
            payload: try JSONEncoder().encode(mismatchedTelemetry)
        )), to: master)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(stateRecorder.last?.phase, .searching)
        XCTAssertNil(stateRecorder.last?.telemetry)
        await transport.stop()
    }

    @MainActor
    func testSanitizedDiagnosticIncludesDeskIdentityButNotSerialPath() throws {
        let report = SanitizedDiagnosticExporter.report(
            settings: AppSettings(),
            snapshots: [:],
            refreshStates: [:],
            deskConnection: .init(
                phase: .connected,
                path: "/dev/cu.usbmodem-private-identifier",
                firmwareVersion: "0.6.0",
                protocolMajor: 1,
                protocolMinor: 1,
                telemetry: .init(
                    firmwareVersion: "0.6.0", uptimeSeconds: 120,
                    freeHeapBytes: 180_000, minimumFreeHeapBytes: 170_000,
                    framesPerSecond: 8.5, resetReason: "usb",
                    invalidFrameCount: 0, handshakeCount: 4, touchCount: 3,
                    touchInterruptCount: 3, touchReadErrorCount: 0,
                    touchPollAttemptCount: 500, touchPollTouchCount: 3,
                    touchControllerPresent: true,
                    lastTouchLatencyMs: 7.5, maximumTouchLatencyMs: 12.0
                )
            )
        )
        XCTAssertEqual(report.desk?.uptimeSeconds, 120)
        XCTAssertEqual(report.desk?.minimumFreeHeapBytes, 170_000)
        XCTAssertEqual(report.desk?.framesPerSecond, 8.5)
        XCTAssertEqual(report.desk?.resetReason, "usb")
        XCTAssertEqual(report.desk?.invalidFrameCount, 0)
        XCTAssertEqual(report.desk?.touchCount, 3)
        XCTAssertEqual(report.desk?.touchReadErrorCount, 0)
        XCTAssertEqual(report.desk?.touchControllerPresent, true)
        XCTAssertEqual(report.desk?.maximumTouchLatencyMs, 12.0)
        let text = try XCTUnwrap(String(data: SanitizedDiagnosticExporter.data(report), encoding: .utf8))
        XCTAssertTrue(text.contains("0.6.0"))
        XCTAssertTrue(text.contains("connected"))
        XCTAssertFalse(text.contains("usbmodem-private-identifier"))
    }

    @MainActor
    func testSoakRecorderStreamsSanitizedTelemetry() throws {
        let report = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchAgentDeskSoak-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: report) }
        let recorder = try NotchAgentDeskSoakRecorder(reportURL: report)
        recorder.record(.init(
            phase: .connected,
            path: "/dev/cu.usbmodem-private-identifier",
            firmwareVersion: "0.6.0",
            protocolMajor: 1,
            protocolMinor: 1,
            telemetry: .init(
                firmwareVersion: "0.6.0", uptimeSeconds: 20, freeHeapBytes: 180_000,
                minimumFreeHeapBytes: 170_000, framesPerSecond: 8.5, resetReason: "usb",
                invalidFrameCount: 0, handshakeCount: 1, touchCount: 0,
                lastTouchLatencyMs: 0, maximumTouchLatencyMs: 0
            )
        ))
        recorder.close()

        let data = try Data(contentsOf: report)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("usbmodem-private-identifier"))
        let line = try XCTUnwrap(text.split(separator: "\n").first)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DeskSoakRecord.self, from: Data(line.utf8))
        XCTAssertEqual(decoded.phase, .connected)
        XCTAssertEqual(decoded.telemetry?.firmwareVersion, "0.6.0")
        XCTAssertTrue(decoded.reliabilityFailures.isEmpty)
    }

    func testRecognizedTransportPeriodicallyRehandshakes() async throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 1_024)
        XCTAssertEqual(openpty(&master, &slave, &name, nil, nil), 0)
        guard master >= 0, slave >= 0 else { return XCTFail("openpty failed") }
        defer { Darwin.close(master); Darwin.close(slave) }
        let path = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let flags = fcntl(master, F_GETFL)
        XCTAssertEqual(fcntl(master, F_SETFL, flags | O_NONBLOCK), 0)
        let stateRecorder = DeskConnectionStateRecorder()
        let transport = NotchAgentDeskSerialTransport(
            candidatePaths: { [path] in [path] },
            stateHandler: { stateRecorder.append($0) }
        )
        await transport.start()

        let firstHello = try await readFrame(from: master, timeout: .seconds(3))
        let decodedHello = try JSONDecoder().decode(DeskHello.self, from: firstHello.payload)
        let acknowledgement = DeskHelloAcknowledgement(
            product: decodedHello.product,
            protocolMajor: decodedHello.protocolMajor,
            protocolMinor: decodedHello.protocolMinor,
            nonce: decodedHello.nonce,
            firmwareVersion: "0.6.4"
        )
        try writeAll(try DeskFrameCodec.encode(.init(
            type: .helloAcknowledgement,
            sequence: 1,
            payload: try JSONEncoder().encode(acknowledgement)
        )), to: master)
        let telemetry = DeskDeviceTelemetry(
            firmwareVersion: "0.6.4", uptimeSeconds: 20, freeHeapBytes: 180_000,
            minimumFreeHeapBytes: 170_000, framesPerSecond: 8.5, resetReason: "usb",
            invalidFrameCount: 0, handshakeCount: 1, touchCount: 0,
            lastTouchLatencyMs: 0, maximumTouchLatencyMs: 0
        )
        try writeAll(try DeskFrameCodec.encode(.init(
            type: .deviceTelemetry,
            sequence: 2,
            payload: try JSONEncoder().encode(telemetry)
        )), to: master)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(stateRecorder.last?.telemetry, telemetry)
        let refreshedHello = try await readFrame(from: master, timeout: .seconds(17))
        XCTAssertEqual(refreshedHello.type, .hello)
        XCTAssertNotEqual(refreshedHello.payload, firstHello.payload)
        let refreshedDecoded = try JSONDecoder().decode(DeskHello.self, from: refreshedHello.payload)
        let refreshedAcknowledgement = DeskHelloAcknowledgement(
            product: refreshedDecoded.product,
            protocolMajor: refreshedDecoded.protocolMajor,
            protocolMinor: refreshedDecoded.protocolMinor,
            nonce: refreshedDecoded.nonce,
            firmwareVersion: "0.6.4"
        )
        try writeAll(try DeskFrameCodec.encode(.init(
            type: .helloAcknowledgement,
            sequence: 3,
            payload: try JSONEncoder().encode(refreshedAcknowledgement)
        )), to: master)
        let refreshedDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (stateRecorder.last?.phase != .connected ||
               stateRecorder.last?.telemetry != telemetry),
              ContinuousClock.now < refreshedDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(stateRecorder.last?.phase, .connected)
        XCTAssertEqual(stateRecorder.last?.telemetry, telemetry)
        await transport.stop()
    }

    func testIncompatibleTransportStaysAvailableForRecovery() async throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 1_024)
        XCTAssertEqual(openpty(&master, &slave, &name, nil, nil), 0)
        guard master >= 0, slave >= 0 else { return XCTFail("openpty failed") }
        defer { Darwin.close(master); Darwin.close(slave) }
        let path = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let flags = fcntl(master, F_GETFL)
        XCTAssertEqual(fcntl(master, F_SETFL, flags | O_NONBLOCK), 0)
        let states = DeskConnectionStateRecorder()
        let transport = NotchAgentDeskSerialTransport(
            candidatePaths: { [path] in [path] },
            stateHandler: { states.append($0) }
        )
        await transport.start()
        let hello = try await readFrame(from: master, timeout: .seconds(3))
        let decoded = try JSONDecoder().decode(DeskHello.self, from: hello.payload)
        let incompatible = DeskHelloAcknowledgement(
            product: decoded.product,
            protocolMajor: decoded.protocolMajor + 1,
            protocolMinor: decoded.protocolMinor,
            nonce: decoded.nonce,
            firmwareVersion: "0.5.0"
        )
        try writeAll(try DeskFrameCodec.encode(.init(
            type: .helloAcknowledgement,
            sequence: 1,
            payload: try JSONEncoder().encode(incompatible)
        )), to: master)
        try await Task.sleep(for: .seconds(6))
        XCTAssertEqual(states.last?.phase, .incompatible)
        XCTAssertEqual(states.last?.path, path)
        await transport.stop()
    }

    func testTransportCompletesConfiguredRehandshakeCycles() async throws {
        let target = Int(ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_REHANDSHAKE_TARGET"] ?? "") ?? 0
        guard target > 0 else {
            throw XCTSkip("Set NOTCHAGENT_DESK_REHANDSHAKE_TARGET to run the reconnect harness.")
        }
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 1_024)
        XCTAssertEqual(openpty(&master, &slave, &name, nil, nil), 0)
        defer { Darwin.close(master); Darwin.close(slave) }
        let path = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let flags = fcntl(master, F_GETFL)
        XCTAssertEqual(fcntl(master, F_SETFL, flags | O_NONBLOCK), 0)
        let transport = NotchAgentDeskSerialTransport(candidatePaths: { [path] in [path] })
        await transport.start()
        for sequence in 1...target {
            let hello = try await readFrame(from: master, timeout: .seconds(17))
            let decoded = try JSONDecoder().decode(DeskHello.self, from: hello.payload)
            let acknowledgement = DeskHelloAcknowledgement(
                product: decoded.product,
                protocolMajor: decoded.protocolMajor,
                protocolMinor: NotchAgentDeskProtocol.protocolMinor,
                nonce: decoded.nonce,
                firmwareVersion: "harness"
            )
            try writeAll(try DeskFrameCodec.encode(.init(
                type: .helloAcknowledgement,
                sequence: UInt32(sequence),
                payload: try JSONEncoder().encode(acknowledgement)
            )), to: master)
        }
        await transport.stop()
    }

    func testReliabilityAssessmentRejectsUnsafeHardwareSignals() {
        let healthy = DeskDeviceTelemetry(
            firmwareVersion: "0.6.0", uptimeSeconds: 60, freeHeapBytes: 180_000,
            minimumFreeHeapBytes: 170_000, framesPerSecond: 18, resetReason: "power_on",
            invalidFrameCount: 0, handshakeCount: 1, touchCount: 2,
            touchInterruptCount: 2, touchReadErrorCount: 0,
            lastTouchLatencyMs: 8, maximumTouchLatencyMs: 12
        )
        XCTAssertTrue(DeskReliabilityAssessment.assess(healthy).passed)
        var unhealthy = healthy
        unhealthy.minimumFreeHeapBytes = 90_000
        unhealthy.framesPerSecond = 4
        unhealthy.maximumTouchLatencyMs = 150
        unhealthy.invalidFrameCount = 1
        unhealthy.touchReadErrorCount = 1
        unhealthy.touchControllerPresent = false
        unhealthy.resetReason = "brownout"
        XCTAssertEqual(
            DeskReliabilityAssessment.assess(unhealthy).failures,
            [
                "minimum_heap_below_threshold", "fps_below_threshold",
                "touch_latency_above_threshold", "touch_read_errors_detected",
                "touch_controller_unavailable",
                "invalid_frames_detected", "unsafe_reset_reason",
            ]
        )
    }

    func testTouchContinuityMonitorRejectsAContactStuckAcrossPolls() {
        var monitor = DeskTouchContinuityMonitor()
        var telemetry = DeskDeviceTelemetry(
            firmwareVersion: "test", uptimeSeconds: 1, freeHeapBytes: 180_000,
            minimumFreeHeapBytes: 170_000, framesPerSecond: 8, resetReason: "usb",
            invalidFrameCount: 0, handshakeCount: 1, touchCount: 0,
            touchInterruptCount: 1, touchReadErrorCount: 0,
            touchPollAttemptCount: 0, touchPollTouchCount: 0,
            touchControllerPresent: true, lastTouchLatencyMs: 0, maximumTouchLatencyMs: 0
        )
        XCTAssertNil(monitor.assess(telemetry))
        for interval in 1...2 {
            telemetry.touchPollAttemptCount = UInt32(interval * 200)
            telemetry.touchPollTouchCount = UInt32(interval * 200)
            telemetry.touchCount = UInt32(interval * 200)
            XCTAssertNil(monitor.assess(telemetry))
        }
        telemetry.touchPollAttemptCount = 600
        telemetry.touchPollTouchCount = 600
        telemetry.touchCount = 600
        XCTAssertEqual(monitor.assess(telemetry), "touch_contact_stuck")

        telemetry.touchPollAttemptCount = 800
        telemetry.touchPollTouchCount = 601
        XCTAssertNil(monitor.assess(telemetry))
    }

    func testTouchContinuityMonitorRejectsPhantomIRQStorm() {
        var monitor = DeskTouchContinuityMonitor()
        var telemetry = DeskDeviceTelemetry(
            firmwareVersion: "test", uptimeSeconds: 100, freeHeapBytes: 180_000,
            minimumFreeHeapBytes: 170_000, framesPerSecond: 8, resetReason: "usb",
            invalidFrameCount: 0, handshakeCount: 1, touchCount: 0,
            touchInterruptCount: 0, touchReadErrorCount: 0,
            touchPollAttemptCount: 100, touchPollTouchCount: 0,
            touchControllerPresent: true, lastTouchLatencyMs: 0, maximumTouchLatencyMs: 0
        )
        XCTAssertNil(monitor.assess(telemetry))

        telemetry.uptimeSeconds = 105
        telemetry.touchCount = 40
        telemetry.touchInterruptCount = 40
        telemetry.touchPollAttemptCount = 105
        XCTAssertNil(monitor.assess(telemetry), "A bounded physical gesture is not an IRQ storm")

        telemetry.uptimeSeconds = 110
        telemetry.touchCount = 104
        telemetry.touchInterruptCount = 104
        telemetry.touchPollAttemptCount = 110
        XCTAssertEqual(monitor.assess(telemetry), "touch_irq_storm")

        var shortWindowMonitor = DeskTouchContinuityMonitor()
        telemetry.uptimeSeconds = 200
        telemetry.touchCount = 0
        telemetry.touchInterruptCount = 0
        telemetry.touchPollAttemptCount = 200
        XCTAssertNil(shortWindowMonitor.assess(telemetry))

        telemetry.uptimeSeconds = 201
        telemetry.touchCount = 11
        telemetry.touchInterruptCount = 11
        telemetry.touchPollAttemptCount = 201
        XCTAssertNil(shortWindowMonitor.assess(telemetry), "Eleven IRQs in one second stays below the storm boundary")

        telemetry.uptimeSeconds = 202
        telemetry.touchCount = 23
        telemetry.touchInterruptCount = 23
        telemetry.touchPollAttemptCount = 202
        XCTAssertEqual(shortWindowMonitor.assess(telemetry), "touch_irq_storm")
    }

    @MainActor
    func testAmbientIntelligencePrioritizesRiskThenFocus() {
        let suite = "NotchAgentDeskTests.Ambient.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(preferences: PreferencesStore(defaults: defaults))
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            capturedAt: now,
            health: .ok,
            session: SessionUsage(usedPercent: 20),
            lastActivityAt: now.addingTimeInterval(-60)
        ))
        XCTAssertEqual(NotchAgentDeskAmbientIntelligence.recommend(store: store, now: now).page, .rhythm)

        store.apply(UsageSnapshot(
            provider: .claudeCode,
            capturedAt: now.addingTimeInterval(1),
            health: .ok,
            session: SessionUsage(usedPercent: 80),
            lastActivityAt: now
        ))
        let risk = NotchAgentDeskAmbientIntelligence.recommend(store: store, now: now.addingTimeInterval(1))
        XCTAssertEqual(risk.page, .now)
        XCTAssertEqual(risk.severity, .warning)
        XCTAssertTrue(risk.reason.contains("20% left"))
    }

    func testOversizedPayloadIsRejectedBeforeEncoding() {
        let payload = Data(repeating: 1, count: NotchAgentDeskProtocol.maximumPayloadBytes + 1)
        XCTAssertThrowsError(try DeskFrameCodec.encode(.init(type: .snapshot, sequence: 1, payload: payload))) {
            XCTAssertEqual($0 as? DeskFrameCodecError, .payloadTooLarge)
        }
    }

    func testFirmwarePackageValidatesHashesAndRejectsTampering() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchAgentDeskPackage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("NotchAgentDesk-factory.bin")
        let flasherURL = directory.appendingPathComponent("esptool")
        let image = Data(repeating: 0xA5, count: 65_536)
        let flasher = Data(repeating: 0x5A, count: 1_048_576)
        try image.write(to: imageURL)
        try flasher.write(to: flasherURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: flasherURL.path)
        let manifest = DeskFirmwareManifest(
            schemaVersion: 2,
            firmwareVersion: "0.6.0",
            chip: "esp32s3",
            imageFile: imageURL.lastPathComponent,
            imageAddress: 0,
            imageSHA256: SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined(),
            sourceSHA256: String(repeating: "a", count: 64),
            flasherFile: flasherURL.lastPathComponent,
            flasherSHA256: SHA256.hash(data: flasher).map { String(format: "%02x", $0) }.joined()
        )
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))

        XCTAssertEqual(try DeskFirmwarePackage.load(from: directory).manifest.firmwareVersion, "0.6.0")
        try Data("tampered".utf8).write(to: imageURL)
        XCTAssertThrowsError(try DeskFirmwarePackage.load(from: directory)) {
            XCTAssertEqual($0 as? DeskFirmwareUpdateError, .integrityFailure)
        }
    }

    func testFirmwarePackageRejectsUnexpectedManifestFieldsAndSymlinks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchAgentDeskPackageStrict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("firmware.bin")
        let flasherURL = directory.appendingPathComponent("esptool")
        let image = Data(repeating: 0xA5, count: 65_536)
        let flasher = Data(repeating: 0x5A, count: 1_048_576)
        try image.write(to: imageURL)
        try flasher.write(to: flasherURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: flasherURL.path)
        let sha: (Data) -> String = {
            SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        }
        let manifest: [String: Any] = [
            "schemaVersion": 2, "firmwareVersion": "0.6.4", "chip": "esp32s3",
            "imageFile": "firmware.bin", "imageAddress": 0,
            "imageSHA256": sha(image), "sourceSHA256": String(repeating: "a", count: 64),
            "flasherFile": "esptool", "flasherSHA256": sha(flasher),
            "unexpected": true,
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: directory.appendingPathComponent("manifest.json")
        )
        XCTAssertThrowsError(try DeskFirmwarePackage.load(from: directory)) {
            XCTAssertEqual($0 as? DeskFirmwareUpdateError, .invalidManifest)
        }

        var cleanManifest = manifest
        cleanManifest.removeValue(forKey: "unexpected")
        try JSONSerialization.data(withJSONObject: cleanManifest).write(
            to: directory.appendingPathComponent("manifest.json")
        )
        try FileManager.default.removeItem(at: imageURL)
        try FileManager.default.createSymbolicLink(
            at: imageURL,
            withDestinationURL: URL(fileURLWithPath: "/dev/null")
        )
        XCTAssertThrowsError(try DeskFirmwarePackage.load(from: directory)) {
            XCTAssertEqual($0 as? DeskFirmwareUpdateError, .integrityFailure)
        }
    }

    func testFirmwareProcessTimesOutAndRejectsNonDevicePaths() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        do {
            _ = try await NotchAgentDeskFirmwareUpdater.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeoutSeconds: 0.05
            )
            XCTFail("A hung firmware process should time out")
        } catch {
            XCTAssertEqual(error as? DeskFirmwareUpdateError, .flashTimedOut)
        }
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(3))
        XCTAssertFalse(NotchAgentDeskFirmwareUpdater.isSupportedSerialDevice("/dev/cu.usbmodem/../../etc/passwd"))
        XCTAssertFalse(NotchAgentDeskFirmwareUpdater.isSupportedSerialDevice("/tmp/cu.usbmodem-fake"))
        XCTAssertFalse(NotchAgentDeskFirmwareUpdater.isSupportedSerialDevice("/dev/null"))
    }

    func testSignedAppFirmwarePackageWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_SIGNED_APP_PACKAGE"] == "1" else {
            throw XCTSkip("Set NOTCHAGENT_DESK_SIGNED_APP_PACKAGE=1 after building the signed app.")
        }
        let appURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("dist/NotchAgent.app", isDirectory: true)
        let bundle = try XCTUnwrap(Bundle(url: appURL))
        let package = try NotchAgentDeskFirmwareUpdater.bundledPackage(bundle: bundle)
        XCTAssertEqual(package.manifest.firmwareVersion, "0.6.16")
    }

    func testFirmwareUpdateRequiresReconnectedMatchingTelemetry() {
        let telemetry = DeskDeviceTelemetry(
            firmwareVersion: "0.6.4", uptimeSeconds: 5, freeHeapBytes: 180_000,
            minimumFreeHeapBytes: 170_000, framesPerSecond: 8, resetReason: "usb",
            invalidFrameCount: 0, handshakeCount: 1, touchCount: 0,
            lastTouchLatencyMs: 0, maximumTouchLatencyMs: 0
        )
        let installed = NotchAgentDeskConnectionState(
            phase: .connected, firmwareVersion: "0.6.4",
            protocolMajor: 1, protocolMinor: 1, telemetry: telemetry
        )
        XCTAssertEqual(
            DeskFirmwareVerification.evaluate(installed, expectedVersion: "0.6.4"),
            .installed
        )
        var stale = installed
        stale.phase = .searching
        XCTAssertEqual(
            DeskFirmwareVerification.evaluate(stale, expectedVersion: "0.6.4"),
            .waiting
        )
        var missingTelemetry = installed
        missingTelemetry.telemetry = nil
        XCTAssertEqual(
            DeskFirmwareVerification.evaluate(missingTelemetry, expectedVersion: "0.6.4"),
            .waiting
        )
        var mismatch = installed
        mismatch.firmwareVersion = "0.6.2"
        XCTAssertEqual(
            DeskFirmwareVerification.evaluate(mismatch, expectedVersion: "0.6.4"),
            .versionMismatch
        )
    }

    func testFirmwareRecoveryEligibilityIncludesIncompatibleAndHandshakeStates() {
        let path = "/dev/cu.usbmodem-test"
        for phase in [
            NotchAgentDeskConnectionState.Phase.handshaking,
            .connected,
            .incompatible,
        ] {
            XCTAssertTrue(DeskFirmwareRecoveryEligibility.canInstall(
                connection: .init(phase: phase, path: path),
                updateState: .ready(version: "0.6.4")
            ))
        }
        XCTAssertFalse(DeskFirmwareRecoveryEligibility.canInstall(
            connection: .searching,
            updateState: .ready(version: "0.6.4")
        ))
        XCTAssertFalse(DeskFirmwareRecoveryEligibility.canInstall(
            connection: .init(phase: .incompatible, path: path),
            updateState: .updating
        ))
        XCTAssertTrue(NotchAgentDeskFirmwareUpdater.trustedApplicationRequirement.contains("anchor apple generic"))
        XCTAssertTrue(
            NotchAgentDeskFirmwareUpdater.trustedApplicationRequirement.contains(
                #"certificate leaf[subject.OU] = "S3YCFYY8SC""#
            )
        )
    }

    func testPhysicalFirmwareUpdateWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_PHYSICAL_UPDATE"] == "1" else {
            throw XCTSkip("Set NOTCHAGENT_DESK_PHYSICAL_UPDATE=1 for the destructive hardware update test.")
        }
        let packageDirectory = ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_PACKAGE_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("dist/NotchAgent.app/Contents/Resources/DeskFirmware", isDirectory: true)
        let package = try DeskFirmwarePackage.load(from: packageDirectory)
        guard package.manifest.firmwareVersion == "0.6.16" else {
            XCTFail(
                "Bundled Desk firmware is \(package.manifest.firmwareVersion), expected 0.6.16. " +
                "Run Scripts/make-notchagent-desk-local-beta1.sh before a physical update."
            )
            return
        }
        let port = try XCTUnwrap(
            ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_PORT"],
            "Set NOTCHAGENT_DESK_PORT to the port returned by notchagent-desk-resolve-port.sh."
        )
        try await NotchAgentDeskFirmwareUpdater.flash(
            package: package,
            port: port
        )
    }

    func testPhysicalTelemetryWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_PHYSICAL_TELEMETRY"] == "1" else {
            throw XCTSkip("Set NOTCHAGENT_DESK_PHYSICAL_TELEMETRY=1 for the physical telemetry test.")
        }
        let port = try XCTUnwrap(
            ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_PORT"],
            "Set NOTCHAGENT_DESK_PORT to the port returned by notchagent-desk-resolve-port.sh."
        )
        let recorder = DeskConnectionStateRecorder()
        let transport = NotchAgentDeskSerialTransport(
            candidatePaths: { [port] },
            stateHandler: { recorder.append($0) }
        )
        await transport.start()

        let duration = max(
            6,
            Int(ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_TELEMETRY_DURATION_SECONDS"] ?? "6") ?? 6
        )
        let reportHandle: FileHandle? = try ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_TELEMETRY_REPORT"].map {
            let url = URL(fileURLWithPath: $0)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw POSIXError(.EIO) }
            return try FileHandle(forWritingTo: url)
        }
        defer { try? reportHandle?.close() }
        let reportEncoder = JSONEncoder()
        reportEncoder.dateEncodingStrategy = .iso8601
        var writtenSampleCount = 0
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(duration))
        do {
            while clock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
                let currentSamples = recorder.telemetrySamples
                if let reportHandle, currentSamples.count > writtenSampleCount {
                    for telemetry in currentSamples.dropFirst(writtenSampleCount) {
                        let record = DeskTimestampedTelemetrySample(capturedAt: Date(), telemetry: telemetry)
                        var line = try reportEncoder.encode(record)
                        line.append(0x0A)
                        try reportHandle.write(contentsOf: line)
                    }
                    try reportHandle.synchronize()
                    writtenSampleCount = currentSamples.count
                }
            }
        } catch {
            await transport.stop()
            throw error
        }

        let state: NotchAgentDeskConnectionState
        let telemetry: DeskDeviceTelemetry
        do {
            state = try XCTUnwrap(recorder.last)
            telemetry = try XCTUnwrap(state.telemetry)
        } catch {
            await transport.stop()
            throw error
        }
        await transport.stop()
        XCTAssertEqual(state.phase, .connected)
        XCTAssertEqual(telemetry.firmwareVersion, "0.6.16")
        XCTAssertGreaterThan(telemetry.freeHeapBytes, 0)
        XCTAssertGreaterThan(telemetry.framesPerSecond, 0)
        let samples = recorder.telemetrySamples
        XCTAssertFalse(samples.isEmpty)
        let failures = samples.enumerated().compactMap { index, sample -> String? in
            let assessment = DeskReliabilityAssessment.assess(sample)
            guard !assessment.passed else { return nil }
            return "sample \(index): \(assessment.failures.joined(separator: ","))"
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
        var touchContinuityMonitor = DeskTouchContinuityMonitor()
        let touchContinuityFailures = samples.compactMap {
            touchContinuityMonitor.assess($0)
        }
        XCTAssertTrue(
            touchContinuityFailures.isEmpty,
            touchContinuityFailures.joined(separator: ",")
        )
        if ProcessInfo.processInfo.environment["NOTCHAGENT_DESK_REQUIRE_TOUCH"] == "1" {
            let touchedSamples = samples.filter { $0.touchCount > 0 }
            let maximumInterrupts = samples.compactMap(\.touchInterruptCount).max() ?? 0
            let maximumReadErrors = samples.compactMap(\.touchReadErrorCount).max() ?? 0
            let maximumPollTouches = samples.compactMap(\.touchPollTouchCount).max() ?? 0
            let controllerPresent = samples.compactMap(\.touchControllerPresent).last
            XCTAssertFalse(
                touchedSamples.isEmpty,
                "No physical touch was received; controller=\(String(describing: controllerPresent)), IRQ=\(maximumInterrupts), pollTouches=\(maximumPollTouches), readErrors=\(maximumReadErrors)"
            )
            XCTAssertTrue(
                touchedSamples.allSatisfy { $0.maximumTouchLatencyMs <= DeskReliabilityAcceptance().maximumTouchLatencyMs },
                "Physical touch latency exceeded the acceptance limit"
            )
        }
    }

    func testPhysicalResetReconnectCyclesWhenExplicitlyEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        let target = Int(environment["NOTCHAGENT_DESK_PHYSICAL_RECONNECT_TARGET"] ?? "") ?? 0
        guard target > 0 else {
            throw XCTSkip("Set NOTCHAGENT_DESK_PHYSICAL_RECONNECT_TARGET for physical reset/reconnect cycles.")
        }
        let port = try XCTUnwrap(
            environment["NOTCHAGENT_DESK_PORT"],
            "Set NOTCHAGENT_DESK_PORT to the port returned by notchagent-desk-resolve-port.sh."
        )
        let flasher = environment["NOTCHAGENT_DESK_FLASHER"]
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("firmware/notchagent_desk/release/esptool").path
        let reportURL = environment["NOTCHAGENT_DESK_RECONNECT_REPORT"].map {
            URL(fileURLWithPath: $0)
        }
        var samples: [DeskPhysicalReconnectSample] = []

        for cycle in 1...target {
            let resetStartedAt = ContinuousClock.now
            let process = Process()
            process.executableURL = URL(fileURLWithPath: flasher)
            process.arguments = [
                "--chip", "esp32s3", "--port", port,
                "--before", "default-reset", "--after", "hard-reset", "run",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "Reset failed at cycle \(cycle)")
            guard process.terminationStatus == 0 else { break }
            let resetCompletedAt = ContinuousClock.now

            let recorder = DeskConnectionStateRecorder()
            let transport = NotchAgentDeskSerialTransport(
                candidatePaths: { [port] },
                stateHandler: { recorder.append($0) }
            )
            await transport.start()
            let telemetry: DeskDeviceTelemetry
            do {
                let deadline = ContinuousClock.now.advanced(by: .seconds(12))
                while recorder.last?.telemetry == nil, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(100))
                }
                telemetry = try XCTUnwrap(recorder.last?.telemetry, "No telemetry after cycle \(cycle)")
            } catch {
                await transport.stop()
                throw error
            }
            await transport.stop()
            let assessment = DeskReliabilityAssessment.assess(telemetry)
            XCTAssertTrue(assessment.passed, "Cycle \(cycle): \(assessment.failures.joined(separator: ","))")
            let telemetryCompletedAt = ContinuousClock.now
            let resetDuration = resetStartedAt.duration(to: resetCompletedAt).components
            let reconnectDuration = resetStartedAt.duration(to: telemetryCompletedAt).components
            let resetMilliseconds = resetDuration.seconds * 1_000
                + resetDuration.attoseconds / 1_000_000_000_000_000
            let reconnectMilliseconds = reconnectDuration.seconds * 1_000
                + reconnectDuration.attoseconds / 1_000_000_000_000_000
            samples.append(.init(
                cycle: cycle,
                reconnectMilliseconds: Int(reconnectMilliseconds),
                resetMilliseconds: Int(resetMilliseconds),
                telemetryMilliseconds: Int(reconnectMilliseconds - resetMilliseconds),
                telemetry: telemetry
            ))
            if let reportURL {
                try JSONEncoder().encode(samples).write(to: reportURL, options: .atomic)
            }
            if cycle == 1 || cycle.isMultiple(of: 10) || cycle == target {
                print("Desk reconnect progress: \(cycle)/\(target)")
            }
            XCTAssertLessThanOrEqual(
                reconnectMilliseconds, 15_000,
                "Cycle \(cycle) exceeded the 15s reconnect gate (reset=\(resetMilliseconds)ms, telemetry=\(reconnectMilliseconds - resetMilliseconds)ms)"
            )
            guard reconnectMilliseconds <= 15_000 else { break }
        }

        XCTAssertEqual(samples.count, target)
    }

    private func readFrame(from descriptor: Int32, timeout: Duration) async throws -> DeskFrame {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var stream = DeskFrameStreamDecoder()
        while clock.now < deadline {
            var bytes = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count > 0 {
                for result in stream.append(Data(bytes.prefix(count))) {
                    if case .success(let frame) = result { return frame }
                }
            } else if count < 0, errno != EAGAIN, errno != EWOULDBLOCK {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw POSIXError(.ETIMEDOUT)
    }

    private func tryReadFrame(from descriptor: Int32) -> DeskFrame? {
        var bytes = [UInt8](repeating: 0, count: 4_096)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        guard count > 0 else { return nil }
        var stream = DeskFrameStreamDecoder()
        for result in stream.append(Data(bytes.prefix(count))) {
            if case .success(let frame) = result { return frame }
        }
        return nil
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return Darwin.write(descriptor, base, buffer.count)
        }
        guard written == data.count else { throw POSIXError(.EIO) }
    }

    @MainActor
    func testSnapshotIsBoundedAndExcludesSensitiveAccountFields() throws {
        let suite = "NotchAgentDeskTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(preferences: PreferencesStore(defaults: defaults))
        let accountID = UUID()
        store.apply(UsageSnapshot(
            provider: .apiAccounts,
            health: .ok,
            note: "secret diagnostic",
            accountUsage: [APIAccountUsage(
                accountID: accountID,
                label: "Private customer label",
                service: .openAI,
                usedPercent: 35,
                resetsAt: nil,
                summary: "private error body",
                monthlySpendUSD: 123.45,
                balanceUSD: 42,
                billingScopeID: "org-secret",
                readStatus: .updated
            )]
        ))

        let data = try JSONEncoder().encode(DeskSnapshotFactory.make(from: store))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(accountID.uuidString))
        XCTAssertFalse(text.contains("Private customer label"))
        XCTAssertFalse(text.contains("secret diagnostic"))
        XCTAssertFalse(text.contains("private error body"))
        XCTAssertFalse(text.contains("org-secret"))
        XCTAssertFalse(text.contains("123.45"))
        XCTAssertFalse(text.contains("openai"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(root["apiServices"])
        let providers = try XCTUnwrap(root["providers"] as? [[String: Any]])
        XCTAssertFalse(providers.contains { ($0["id"] as? String) == ProviderID.apiAccounts.rawValue })
        XCTAssertLessThan(data.count, NotchAgentDeskProtocol.maximumPayloadBytes)
    }
}

private final class DeskConnectionStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [NotchAgentDeskConnectionState] = []

    var last: NotchAgentDeskConnectionState? {
        lock.withLock { states.last }
    }

    var telemetrySamples: [DeskDeviceTelemetry] {
        lock.withLock { states.compactMap(\.telemetry) }
    }

    func append(_ state: NotchAgentDeskConnectionState) {
        lock.withLock { states.append(state) }
    }
}

private struct DeskPhysicalReconnectSample: Codable {
    var cycle: Int
    var reconnectMilliseconds: Int
    var resetMilliseconds: Int
    var telemetryMilliseconds: Int
    var telemetry: DeskDeviceTelemetry
}

private struct DeskTimestampedTelemetrySample: Codable {
    var capturedAt: Date
    var telemetry: DeskDeviceTelemetry
}
