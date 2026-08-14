#!/usr/bin/env swift

import AppKit
import Foundation
import Vision

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

guard let image = NSImage(contentsOf: imageURL),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("INVALID: onboarding QR cannot be rendered.\n".utf8))
    exit(1)
}

let request = VNDetectBarcodesRequest()
try VNImageRequestHandler(cgImage: cgImage).perform([request])
let payloads = (request.results ?? []).compactMap(\.payloadStringValue)
guard payloads == [expected] else {
    FileHandle.standardError.write(Data("INVALID: onboarding QR payload does not match its URL contract.\n".utf8))
    exit(1)
}

print("PASS: onboarding QR decodes to the canonical public guide.")
