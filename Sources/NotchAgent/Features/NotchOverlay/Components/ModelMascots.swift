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

/// The OpenAI knot as an 8-bit pixel sprite — extracted verbatim from the
/// approved blue-gradient 3D reference (19/08). The sprite carries its own
/// blue palette, so no template/tint: the knot reads on dark AND light
/// panels. Canvas fallback if the asset is missing.
struct OpenAIGlyph: View {
    /// Mid tone of the sprite's blue gradient — the fallback knot draws
    /// in this tone so a missing asset still reads as the knot.
    private static let knotBlue = Color(red: 129.0 / 255.0, green: 151.0 / 255.0, blue: 244.0 / 255.0)

    private var image: NSImage? {
        guard let url = AssetBundle.url(forResource: "Mascots/openai-glyph", withExtension: "png")
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
                            context.fill(Path(rect), with: .color(Self.knotBlue))
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
