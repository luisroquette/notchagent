import SwiftUI

/// Pixel-art mascots for the model pages — extracted verbatim from the
/// approved V7 mockup (one sprite per Claude family, one OpenAI glyph for
/// every OpenAI row). Ships as PNG assets in `Resources/Mascots`; the
/// procedural bean is only a fallback when the asset is missing (e.g. bare
/// `swift run` without the bundle).
struct ClaudeMascot: View {
    /// Asset name under Resources/Mascots, e.g. "claude-haiku".
    var name: String
    var tint: Color = Theme.coral

    private var image: NSImage? {
        guard let url = AssetBundle.url(forResource: "Mascots/\(name)", withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                fallbackBean
            }
        }
        .accessibilityHidden(true)
    }

    private var fallbackBean: some View {
        Canvas { context, size in
            let grid: [[Int]] = [
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
            let rows = grid.count
            let cols = grid[0].count
            let pixel = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let originX = (size.width - pixel * CGFloat(cols)) / 2
            let originY = (size.height - pixel * CGFloat(rows)) / 2

            for (rowIndex, row) in grid.enumerated() {
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
    }
}

/// The OpenAI knot logo as a white pixel glyph — extracted verbatim from the
/// approved V7 mockup. Canvas fallback if the asset is missing.
struct OpenAIGlyph: View {
    /// Follows the panel theme — near-white on the black panel, dark ink
    /// on the light one. A fixed white glyph vanishes on a white card.
    var tint: Color = Theme.textPrimary

    private var image: NSImage? {
        guard let url = AssetBundle.url(forResource: "Mascots/openai-glyph", withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let image {
                // Template rendering: the PNG's alpha IS the glyph; the
                // tint colors it per theme. Without it the baked white
                // pixels vanish on the light panel.
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .foregroundStyle(tint)
            } else {
                Canvas { context, size in
                    let grid: [[Int]] = [
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
                    let rows = grid.count
                    let cols = grid[0].count
                    let pixel = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
                    let originX = (size.width - pixel * CGFloat(cols)) / 2
                    let originY = (size.height - pixel * CGFloat(rows)) / 2

                    for (rowIndex, row) in grid.enumerated() {
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
            }
        }
        .accessibilityHidden(true)
    }
}
