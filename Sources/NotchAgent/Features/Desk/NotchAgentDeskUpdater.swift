import CryptoKit
import Darwin
import Foundation
import Security

struct DeskFirmwareManifest: Codable, Sendable, Equatable {
    var schemaVersion: Int
    var firmwareVersion: String
    var chip: String
    var imageFile: String
    var imageAddress: UInt32
    var imageSHA256: String
    var sourceSHA256: String
    var flasherFile: String
    var flasherSHA256: String
}

struct DeskFirmwarePackage: Sendable, Equatable {
    var manifest: DeskFirmwareManifest
    var imageURL: URL
    var flasherURL: URL

    static func load(from directory: URL) throws -> Self {
        let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
        guard isRegularFile(manifestURL, sizeRange: 1...65_536) else {
            throw DeskFirmwareUpdateError.invalidManifest
        }
        let data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        let object = try JSONSerialization.jsonObject(with: data)
        let expectedKeys: Set<String> = [
            "schemaVersion", "firmwareVersion", "chip", "imageFile", "imageAddress",
            "imageSHA256", "sourceSHA256", "flasherFile", "flasherSHA256",
        ]
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == expectedKeys else {
            throw DeskFirmwareUpdateError.invalidManifest
        }
        let manifest = try JSONDecoder().decode(DeskFirmwareManifest.self, from: data)
        guard manifest.schemaVersion == 2,
              manifest.chip == "esp32s3",
              isSafeFilename(manifest.imageFile, extension: "bin"),
              isSafeFilename(manifest.flasherFile, extension: nil),
              manifest.imageAddress == 0,
              isSemVer(manifest.firmwareVersion),
              isSHA256(manifest.imageSHA256),
              isSHA256(manifest.sourceSHA256),
              isSHA256(manifest.flasherSHA256)
        else { throw DeskFirmwareUpdateError.invalidManifest }

        let imageURL = directory.appendingPathComponent(manifest.imageFile, isDirectory: false)
        let flasherURL = directory.appendingPathComponent(manifest.flasherFile, isDirectory: false)
        guard isRegularFile(imageURL, sizeRange: 65_536...16_777_216),
              isRegularFile(flasherURL, sizeRange: 1_048_576...67_108_864),
              FileManager.default.isReadableFile(atPath: imageURL.path),
              FileManager.default.isExecutableFile(atPath: flasherURL.path),
              try sha256(imageURL) == manifest.imageSHA256.lowercased(),
              try sha256(flasherURL) == manifest.flasherSHA256.lowercased()
        else { throw DeskFirmwareUpdateError.integrityFailure }
        return Self(manifest: manifest, imageURL: imageURL, flasherURL: flasherURL)
    }

    private static func isSafeFilename(_ value: String, extension expectedExtension: String?) -> Bool {
        guard !value.isEmpty,
              value == URL(fileURLWithPath: value).lastPathComponent,
              !value.contains("/"),
              !value.contains("\\")
        else { return false }
        return expectedExtension.map { URL(fileURLWithPath: value).pathExtension == $0 } ?? true
    }

    private static func isSemVer(_ value: String) -> Bool {
        value.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.wholeMatch(of: /[0-9a-fA-F]{64}/) != nil
    }

    private static func isRegularFile(_ url: URL, sizeRange: ClosedRange<Int64>) -> Bool {
        var information = stat()
        guard lstat(url.path, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG else { return false }
        return sizeRange.contains(information.st_size)
    }

    private static func sha256(_ url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum DeskFirmwareUpdateError: LocalizedError, Equatable {
    case packageUnavailable
    case invalidManifest
    case integrityFailure
    case invalidDevice
    case flashFailed
    case flashTimedOut
    case verificationFailed
    case invalidApplicationSignature

    var errorDescription: String? {
        switch self {
        case .packageUnavailable: "Firmware package is not bundled."
        case .invalidManifest: "Firmware manifest is invalid."
        case .integrityFailure: "Firmware package integrity check failed."
        case .invalidDevice: "The selected serial device is not supported."
        case .flashFailed: "The device could not be updated. Reconnect it and retry."
        case .flashTimedOut: "The firmware update exceeded 120 seconds and was stopped. Reconnect the device and retry."
        case .verificationFailed: "The device rebooted, but the installed firmware could not be verified."
        case .invalidApplicationSignature: "The app signature is invalid, so bundled firmware cannot be trusted."
        }
    }
}

enum DeskFirmwareVerification: Equatable {
    case waiting
    case installed
    case versionMismatch

    static func evaluate(
        _ state: NotchAgentDeskConnectionState,
        expectedVersion: String
    ) -> Self {
        guard state.phase == .connected else { return .waiting }
        if let firmwareVersion = state.firmwareVersion,
           firmwareVersion != expectedVersion {
            return .versionMismatch
        }
        guard state.firmwareVersion == expectedVersion,
              state.telemetry?.firmwareVersion == expectedVersion else {
            return .waiting
        }
        return .installed
    }
}

enum NotchAgentDeskUpdateState: Sendable, Equatable {
    case unavailable
    case ready(version: String)
    case updating
    case succeeded(version: String)
    case failed(message: String)
}

enum DeskFirmwareRecoveryEligibility {
    static func canInstall(
        connection: NotchAgentDeskConnectionState,
        updateState: NotchAgentDeskUpdateState
    ) -> Bool {
        guard connection.path != nil else { return false }
        guard connection.phase == .connected ||
              connection.phase == .incompatible ||
              connection.phase == .handshaking
        else { return false }
        switch updateState {
        case .unavailable, .updating:
            return false
        case .ready, .succeeded, .failed:
            return true
        }
    }
}

enum NotchAgentDeskFirmwareUpdater {
    static let trustedApplicationRequirement =
        #"identifier "br.com.lfrprojects.notchagent" and anchor apple generic and certificate leaf[subject.OU] = "S3YCFYY8SC""#

    static func bundledPackage(bundle: Bundle = .main) throws -> DeskFirmwarePackage {
        try verifyBundleSignature(bundle)
        guard let resources = bundle.resourceURL else { throw DeskFirmwareUpdateError.packageUnavailable }
        let directory = resources.appendingPathComponent("DeskFirmware", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw DeskFirmwareUpdateError.packageUnavailable
        }
        return try DeskFirmwarePackage.load(from: directory)
    }

    static func flash(package: DeskFirmwarePackage, port: String) async throws {
        guard isSupportedSerialDevice(port),
              NotchAgentDeskSerialTransport.defaultCandidatePaths().contains(port)
        else { throw DeskFirmwareUpdateError.invalidDevice }

        let result = try await runProcess(
            executableURL: package.flasherURL,
            arguments: [
                "--chip", package.manifest.chip,
                "--port", port,
                "--baud", "921600",
                "--before", "default-reset",
                "--after", "hard-reset",
                "write-flash",
                String(format: "0x%x", package.manifest.imageAddress),
                package.imageURL.path,
            ],
            timeoutSeconds: 120
        )
        guard result == 0 else { throw DeskFirmwareUpdateError.flashFailed }
    }

    static func runProcess(
        executableURL: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) async throws -> Int32 {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            // esptool emits animated progress output. Never retain it: a full
            // pipe blocks the flasher mid-update and raw logs are not useful
            // or appropriate for the sanitized customer diagnostic.
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning, Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            guard process.isRunning else { return process.terminationStatus }
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < terminationDeadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            throw DeskFirmwareUpdateError.flashTimedOut
        }.value
    }

    static func isSupportedSerialDevice(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.deletingLastPathComponent().path == "/dev",
              url.lastPathComponent.hasPrefix("cu.usbmodem") else { return false }
        var information = stat()
        return lstat(url.path, &information) == 0 && information.st_mode & S_IFMT == S_IFCHR
    }

    private static func verifyBundleSignature(_ bundle: Bundle) throws {
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecRequirementCreateWithString(
                trustedApplicationRequirement as CFString,
                [],
                &requirement
              ) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(
                staticCode,
                SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
                requirement
              ) == errSecSuccess else {
            throw DeskFirmwareUpdateError.invalidApplicationSignature
        }
    }
}
