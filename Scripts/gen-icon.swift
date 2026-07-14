#!/usr/bin/env swift
// Renders the app icon (pixel mascot on a black rounded tile) to a 1024px PNG.
// Usage: swift Scripts/gen-icon.swift <output.png>
import AppKit

let grid: [[Int]] = [
    [0, 1, 1, 0, 0, 1, 1, 0],
    [1, 1, 1, 1, 1, 1, 1, 1],
    [1, 2, 2, 1, 1, 2, 2, 1],
    [1, 1, 1, 1, 1, 1, 1, 1],
    [1, 1, 1, 1, 1, 1, 1, 1],
    [0, 1, 0, 1, 1, 0, 1, 0],
]

let size = 1024
let coral = NSColor(red: 0.855, green: 0.467, blue: 0.341, alpha: 1)
let chassis = NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)

let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
    // macOS icon grid: content tile with margins, continuous-rounded corners.
    let inset = rect.insetBy(dx: 100, dy: 100)
    let tile = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    chassis.setFill()
    tile.fill()

    // Coral hairline near the top — the notch signature.
    coral.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: inset.minX + 120, y: inset.minY + 118, width: inset.width - 240, height: 14), xRadius: 7, yRadius: 7).fill()

    // Mascot.
    let cols = grid[0].count
    let rows = grid.count
    let pixel: CGFloat = 74
    let originX = rect.midX - pixel * CGFloat(cols) / 2
    let originY = rect.midY - pixel * CGFloat(rows) / 2 + 40
    for (rowIndex, row) in grid.enumerated() {
        for (colIndex, cell) in row.enumerated() where cell != 0 {
            let pixelRect = NSRect(
                x: originX + CGFloat(colIndex) * pixel,
                y: originY + CGFloat(rowIndex) * pixel,
                width: pixel * 0.92,
                height: pixel * 0.92
            )
            (cell == 2 ? chassis.blended(withFraction: 0.35, of: .black) ?? chassis : coral).setFill()
            NSBezierPath(roundedRect: pixelRect, xRadius: 8, yRadius: 8).fill()
        }
    }
    return true
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: gen-icon.swift <output.png>\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
var proposedRect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
    fputs("render failed\n", stderr)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
rep.size = NSSize(width: size, height: size)
guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("png encode failed\n", stderr)
    exit(1)
}
try data.write(to: output)
print("icon written to \(output.path)")
