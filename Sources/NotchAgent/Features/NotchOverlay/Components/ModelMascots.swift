import SwiftUI

/// Pixel-art mascots for the model pages, matching the approved V7 design:
/// a smooth bean/egg-shaped orange body with two big round eyes, no mouth,
/// no arms — the Anthropic fuel-gauge spirit, one shape for every family.
/// (1 = body, 2 = eye)
struct ClaudeMascot: View {
    var tint: Color = Theme.coral

    private static let grid: [[Int]] = [
        [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
        [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
        [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
        [0, 1, 1, 1, 1, 2, 2, 1, 1, 2, 2, 1, 1, 1, 1, 0],
        [0, 1, 1, 1, 1, 2, 2, 1, 1, 2, 2, 1, 1, 1, 1, 0],
        [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
        [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
        [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
    ]

    var body: some View {
        Canvas { context, size in
            let rows = Self.grid.count
            let cols = Self.grid[0].count
            let pixel = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let originX = (size.width - pixel * CGFloat(cols)) / 2
            let originY = (size.height - pixel * CGFloat(rows)) / 2

            for (rowIndex, row) in Self.grid.enumerated() {
                for (colIndex, cell) in row.enumerated() where cell != 0 {
                    let rect = CGRect(
                        x: originX + CGFloat(colIndex) * pixel,
                        y: originY + CGFloat(rowIndex) * pixel,
                        width: pixel * 0.92,
                        height: pixel * 0.92
                    )
                    let color: Color = cell == 2 ? Color.black.opacity(0.85) : tint
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The OpenAI knot logo as a white pixel glyph — six thin interlocking loops
/// around a center, one icon for every OpenAI model row.
struct OpenAIGlyph: View {
    var tint: Color = Color(red: 0.96, green: 0.96, blue: 0.97)

    private static let grid: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0],
        [0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0],
        [0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0],
        [0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0],
        [0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0],
        [0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ]

    var body: some View {
        Canvas { context, size in
            let rows = Self.grid.count
            let cols = Self.grid[0].count
            let pixel = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let originX = (size.width - pixel * CGFloat(cols)) / 2
            let originY = (size.height - pixel * CGFloat(rows)) / 2

            for (rowIndex, row) in Self.grid.enumerated() {
                for (colIndex, cell) in row.enumerated() where cell != 0 {
                    let rect = CGRect(
                        x: originX + CGFloat(colIndex) * pixel,
                        y: originY + CGFloat(rowIndex) * pixel,
                        width: pixel * 0.92,
                        height: pixel * 0.92
                    )
                    context.fill(Path(rect), with: .color(tint))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
