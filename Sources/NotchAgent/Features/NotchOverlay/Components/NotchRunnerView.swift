import SwiftUI

/// Chrome-dino homage: a tiny pixel Clawd endlessly running a track that
/// passes UNDER the physical camera housing. Obstacles stream in from the
/// right wing, vanish beneath the notch and re-emerge on the left, where the
/// mascot hops over them. Fully procedural (time-driven, no state), capped at
/// 20 fps so the always-visible bar stays battery-friendly.
struct NotchRunnerView: View {
    /// 0 = full speed; 1 = maximum distress (runner slows and sweats… kidding: it just runs).
    var tint: Color = Theme.coral

    // Runner sprite, 2 gait frames (legs alternate). 0 empty · 1 body · 2 eye.
    private static let gaitA: [[Int]] = [
        [0, 1, 1, 0, 0, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 2, 1, 1, 1, 2, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [0, 1, 0, 0, 1, 0, 0, 0],
    ]
    private static let gaitB: [[Int]] = [
        [0, 1, 1, 0, 0, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 2, 1, 1, 1, 2, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [0, 0, 1, 0, 0, 0, 1, 0],
    ]

    private let runnerX: CGFloat = 12
    private let speed: CGFloat = 46          // pt/s, dino-game cruising pace
    private let obstacleSpacing: [CGFloat] = [170, 240, 205, 290]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            Canvas { graphics, size in
                let t = context.date.timeIntervalSinceReferenceDate
                draw(in: graphics, size: size, time: t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let groundY = size.height - 1.5

        // Dotted ground, like the dino game's desert floor.
        var ground = Path()
        var dashX: CGFloat = -CGFloat(time * Double(speed)).truncatingRemainder(dividingBy: 12)
        while dashX < size.width {
            ground.move(to: CGPoint(x: max(dashX, 0), y: groundY))
            ground.addLine(to: CGPoint(x: min(dashX + 6, size.width), y: groundY))
            dashX += 12
        }
        context.stroke(ground, with: .color(tint.opacity(0.25)), lineWidth: 1)

        // Obstacles: right → left, looping over the full track (they cross
        // beneath the physical notch between the two visible gaps).
        let loop = size.width + 60
        var nextObstacleDistance = CGFloat.greatestFiniteMagnitude
        for (index, offset) in obstacleOffsets.enumerated() {
            let x = loop - (CGFloat(time * Double(speed)) + offset)
                .truncatingRemainder(dividingBy: loop)
            drawObstacle(in: context, x: x, groundY: groundY, variant: index)
            let distance = x - runnerX
            if distance > -6, distance < nextObstacleDistance {
                nextObstacleDistance = distance
            }
        }

        // Jump: a clean parabola timed to clear the nearest incoming obstacle.
        var jumpHeight: CGFloat = 0
        if nextObstacleDistance < 38 {
            let progress = 1 - max(nextObstacleDistance, -6) / 38   // 0 → 1.2
            jumpHeight = sin(min(progress, 1) * .pi) * 13
        }

        // Runner sprite, gait frames at 8 fps.
        let frame = Int(time * 8) % 2 == 0 ? Self.gaitA : Self.gaitB
        let grid = jumpHeight > 1 ? Self.gaitA : frame   // legs tucked mid-air
        let pixel: CGFloat = 2.5
        let spriteHeight = CGFloat(grid.count) * pixel
        let originY = groundY - spriteHeight - jumpHeight
        for (row, cells) in grid.enumerated() {
            for (col, cell) in cells.enumerated() where cell != 0 {
                let rect = CGRect(
                    x: runnerX + CGFloat(col) * pixel,
                    y: originY + CGFloat(row) * pixel,
                    width: pixel * 0.9,
                    height: pixel * 0.9
                )
                context.fill(
                    Path(rect),
                    with: .color(cell == 2 ? Color.black.opacity(0.9) : tint)
                )
            }
        }
    }

    private var obstacleOffsets: [CGFloat] {
        var offsets: [CGFloat] = []
        var accumulated: CGFloat = 0
        for spacing in obstacleSpacing {
            accumulated += spacing
            offsets.append(accumulated)
        }
        return offsets
    }

    /// Tiny pixel cactus/block, two variants for rhythm.
    private func drawObstacle(in context: GraphicsContext, x: CGFloat, groundY: CGFloat, variant: Int) {
        let pixel: CGFloat = 2.5
        let columns: [[Int]] = variant % 2 == 0
            ? [[0, 1, 0], [1, 1, 1], [0, 1, 0], [0, 1, 0]]   // cactus
            : [[1, 1], [1, 1], [1, 1]]                        // block
        let height = CGFloat(columns.count) * pixel
        for (row, cells) in columns.enumerated() {
            for (col, cell) in cells.enumerated() where cell == 1 {
                let rect = CGRect(
                    x: x + CGFloat(col) * pixel,
                    y: groundY - height + CGFloat(row) * pixel,
                    width: pixel * 0.9,
                    height: pixel * 0.9
                )
                context.fill(Path(rect), with: .color(tint.opacity(0.7)))
            }
        }
    }
}
