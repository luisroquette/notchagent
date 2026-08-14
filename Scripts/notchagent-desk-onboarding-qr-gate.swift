#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: notchagent-desk-onboarding-qr-gate.swift QR.svg expected-url.txt\n".utf8))
    exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
let contractURL = URL(fileURLWithPath: CommandLine.arguments[2])
let expected = try String(contentsOf: contractURL, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let expectedURL = URL(string: expected),
      expectedURL.scheme == "https",
      expectedURL.host == "github.com",
      expectedURL.path == "/luisroquette/notchagent/blob/master/docs/NOTCHAGENT_DESK_ONBOARDING.md" else {
    FileHandle.standardError.write(Data("INVALID: onboarding URL contract is not the canonical public guide.\n".utf8))
    exit(1)
}

let temporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("notchagent-qr-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
let generatedURL = temporaryDirectory.appendingPathComponent("expected.svg")

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["qrencode", "-l", "M", "-t", "SVG", "-o", generatedURL.path, expected]
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice
do {
    try process.run()
    process.waitUntilExit()
} catch {
    FileHandle.standardError.write(Data("NOT READY: qrencode is required for deterministic QR validation.\n".utf8))
    exit(2)
}
guard process.terminationReason == .exit, process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("INVALID: canonical onboarding QR could not be generated.\n".utf8))
    exit(1)
}

guard let actual = try? Data(contentsOf: imageURL),
      let generated = try? Data(contentsOf: generatedURL),
      actual == generated else {
    FileHandle.standardError.write(Data("INVALID: onboarding QR payload does not match its URL contract.\n".utf8))
    exit(1)
}

print("PASS: onboarding QR deterministically matches the canonical public guide.")
