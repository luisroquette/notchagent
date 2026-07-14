import SwiftUI

/// Tiny pixel-art mascot drawn procedurally (no assets) — the app's signature
/// mark, a nod to the claude-usage-stick's Clawd. 0 = empty, 1 = body, 2 = eye.
struct PixelGlyph: View {
    var tint: Color = Theme.coral
    /// 0–1: droops the ears and dims the body as usage gets critical.
    var distress: Double = 0

    private static let grid: [[Int]] = [
        [0, 1, 1, 0, 0, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 2, 2, 1, 1, 2, 2, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [0, 1, 0, 1, 1, 0, 1, 0],
    ]

    var body: some View {
        Canvas { context, size in
            let rows = Self.grid.count
            let cols = Self.grid[0].count
        let pixel = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let originX = (size.width - pixel * CGFloat(cols)) / 2
            let originY = (size.height - pixel * CGFloat(rows)) / 2
            let bodyColor = tint.opacity(1 - distress * 0.35)

            for (rowIndex, row) in Self.grid.enumerated() {
                for (colIndex, cell) in row.enumerated() where cell != 0 {
                    // Distress: drop the outer ear pixels.
                    if distress > 0.6, rowIndex == 0, cell == 1 { continue }
                    let rect = CGRect(
                        x: originX + CGFloat(colIndex) * pixel,
                        y: originY + CGFloat(rowIndex) * pixel,
                        width: pixel * 0.92,
                        height: pixel * 0.92
                    )
                    let color: Color = cell == 2 ? Color.black.opacity(0.85) : bodyColor
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}
