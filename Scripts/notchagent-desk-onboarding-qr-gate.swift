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
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 980,
        pixelsHigh: 980,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("INVALID: onboarding QR cannot be rendered.\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.setFillColor(NSColor.white.cgColor)
context.cgContext.fill(CGRect(x: 0, y: 0, width: 980, height: 980))
image.draw(
    in: NSRect(x: 0, y: 0, width: 980, height: 980),
    from: .zero,
    operation: .copy,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.none]
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let cgImage = bitmap.cgImage else {
    FileHandle.standardError.write(Data("INVALID: onboarding QR raster is unavailable.\n".utf8))
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
