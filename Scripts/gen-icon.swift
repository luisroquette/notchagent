#!/usr/bin/env swift
// Renders the app icon from the committed brand icon (Resources/AppIcon.png).
// Usage: swift Scripts/gen-icon.swift <output.png>
import AppKit

guard CommandLine.arguments.count > 1 else {
    fputs("usage: gen-icon.swift <output.png>\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

guard let source = NSImage(contentsOfFile: "Resources/AppIcon.png") else {
    fputs("Resources/AppIcon.png não encontrado\n", stderr)
    exit(1)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
    return true
}

var proposedRect = NSRect(origin: .zero, size: size)
guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
    fputs("render failed\n", stderr)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
rep.size = size
guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("png encode failed\n", stderr)
    exit(1)
}
try data.write(to: output)
print("icon written to \(output.path)")
