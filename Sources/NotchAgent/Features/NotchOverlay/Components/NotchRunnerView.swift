import SwiftUI

/// Chrome-dino homage wired to the real session gauge: the obstacles ARE your
/// tokens running out. As the 5h window drains, the world speeds up and
/// obstacles pack tighter (and take the state color); at 0% the run ends in an
/// 8-bit GAME OVER until the window resets. Fully procedural, 20 fps cap.
struct NotchRunnerView: View {
    /// 0–100, drives difficulty (speed + obstacle density).
    var usedPercent: Double = 0
    /// True when the window is empty (or the API says blocked).
    var isGameOver: Bool = false
    /// Shown as "NEW RUN 18:40" on the game-over screen.
    var resetsAt: Date?
    /// State color for the obstacles (the tokens running out).
    var obstacleTint: Color = Theme.coralDim
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
    /// Fallen mascot: lying flat, legs up — eyes drawn as X at render time.
    private static let dead: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 1, 0, 0, 1, 0, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 2, 1, 1, 1, 2, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
    ]

    private let runnerX: CGFloat = 12
    private let baseSpeed: CGFloat = 46
    private let baseSpacing: [CGFloat] = [170, 240, 205, 290]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            Canvas { graphics, size in
                let t = context.date.timeIntervalSinceReferenceDate
                if isGameOver {
                    drawGameOver(in: graphics, size: size, time: t)
                } else {
                    drawRun(in: graphics, size: size, time: t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Difficulty from the gauge

    private var difficulty: Double { min(max(usedPercent, 0), 100) / 100 }
    /// 46 pt/s relaxed → 112 pt/s at the edge of the window.
    private var speed: CGFloat { baseSpeed + CGFloat(difficulty) * 66 }
    /// Obstacles pack up to ~2× tighter as tokens drain.
    private var spacingScale: CGFloat { 1 - CGFloat(difficulty) * 0.52 }

    // MARK: Running

    private func drawRun(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let groundY = size.height - 1.5
        drawGround(in: context, size: size, groundY: groundY, scroll: CGFloat(time * Double(speed)))

        // Obstacles: right → left, looping over the full track.
        let loop = (size.width + 60) * spacingScale + size.width * (1 - spacingScale)
        var nextObstacleDistance = CGFloat.greatestFiniteMagnitude
        for (index, offset) in obstacleOffsets.enumerated() {
            let x = loop - (CGFloat(time * Double(speed)) + offset * spacingScale)
                .truncatingRemainder(dividingBy: loop)
            drawObstacle(in: context, x: x, groundY: groundY, variant: index)
            let distance = x - runnerX
            if distance > -6, distance < nextObstacleDistance {
                nextObstacleDistance = distance
            }
        }

        // Jump parabola timed to clear the nearest incoming obstacle.
        var jumpHeight: CGFloat = 0
        if nextObstacleDistance < 38 {
            let progress = 1 - max(nextObstacleDistance, -6) / 38
            jumpHeight = sin(min(progress, 1) * .pi) * 13
        }

        // Gait speeds up with the world.
        let gaitFPS = 8.0 + difficulty * 6
        let frame = Int(time * gaitFPS) % 2 == 0 ? Self.gaitA : Self.gaitB
        let grid = jumpHeight > 1 ? Self.gaitA : frame
        drawSprite(grid, in: context, x: runnerX, groundY: groundY - jumpHeight, deadEyes: false)
    }

    // MARK: Game over

    private func drawGameOver(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let groundY = size.height - 1.5
        // Frozen, solid ground.
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: groundY))
        ground.addLine(to: CGPoint(x: size.width, y: groundY))
        context.stroke(ground, with: .color(Theme.danger.opacity(0.4)), lineWidth: 1)

        drawSprite(Self.dead, in: context, x: runnerX, groundY: groundY, deadEyes: true)

        // Arcade blink at ~1.6 Hz.
        let blinkOn = Int(time * 1.6) % 2 == 0
        // Compact bars hide their center under the camera — anchor the text
        // to the right visible gap there; center it on wide (expanded) tracks.
        let narrow = size.width < 420
        let anchorX = narrow ? size.width - 34 : size.width / 2
        if blinkOn {
            context.draw(
                Text("GAME OVER")
                    .font(Theme.label(narrow ? 7.5 : 11))
                    .foregroundStyle(Theme.danger),
                at: CGPoint(x: anchorX, y: narrow ? groundY - 14 : groundY - 15)
            )
        }
        if !narrow, let resetsAt {
            context.draw(
                Text("NEW RUN \(Format.time(resetsAt))")
                    .font(Theme.label(6.5))
                    .foregroundStyle(Theme.textFaint),
                at: CGPoint(x: anchorX, y: groundY - 5)
            )
        }
    }

    // MARK: Shared drawing

    private func drawGround(in context: GraphicsContext, size: CGSize, groundY: CGFloat, scroll: CGFloat) {
        var ground = Path()
        var dashX: CGFloat = -scroll.truncatingRemainder(dividingBy: 12)
        while dashX < size.width {
            ground.move(to: CGPoint(x: max(dashX, 0), y: groundY))
            ground.addLine(to: CGPoint(x: min(dashX + 6, size.width), y: groundY))
            dashX += 12
        }
        context.stroke(ground, with: .color(tint.opacity(0.25)), lineWidth: 1)
    }

    private func drawSprite(
        _ grid: [[Int]],
        in context: GraphicsContext,
        x: CGFloat,
        groundY: CGFloat,
        deadEyes: Bool
    ) {
        let pixel: CGFloat = 2.5
        let spriteHeight = CGFloat(grid.count) * pixel
        let originY = groundY - spriteHeight
        for (row, cells) in grid.enumerated() {
            for (col, cell) in cells.enumerated() where cell != 0 {
                let rect = CGRect(
                    x: x + CGFloat(col) * pixel,
                    y: originY + CGFloat(row) * pixel,
                    width: pixel * 0.9,
                    height: pixel * 0.9
                )
                if cell == 2, deadEyes {
                    // Classic X eyes.
                    var cross = Path()
                    cross.move(to: CGPoint(x: rect.minX, y: rect.minY))
                    cross.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    cross.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                    cross.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                    context.stroke(cross, with: .color(Color.black.opacity(0.9)), lineWidth: 0.8)
                } else {
                    context.fill(
                        Path(rect),
                        with: .color(cell == 2 ? Color.black.opacity(0.9) : tint)
                    )
                }
            }
        }
    }

    private var obstacleOffsets: [CGFloat] {
        var offsets: [CGFloat] = []
        var accumulated: CGFloat = 0
        for spacing in baseSpacing {
            accumulated += spacing
            offsets.append(accumulated)
        }
        return offsets
    }

    /// Pixel cactus/block in the state color — the tokens running out.
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
                context.fill(Path(rect), with: .color(obstacleTint))
            }
        }
    }
}

extension UsageStore {
    /// Game state derived from the Claude session gauge: the run mirrors the
    /// window that actually limits the user's day.
    var runnerGame: (used: Double, gameOver: Bool, resetsAt: Date?, obstacleTint: Color) {
        let snapshot = snapshots[.claudeCode]
        let used = snapshot?.session?.usedPercent ?? 0
        let blocked = snapshot?.quotaStatus == .blocked
        let tint = Theme.ramp(
            used,
            warningAt: settings.warningThresholdPercent,
            criticalAt: settings.criticalThresholdPercent
        )
        return (used, used >= 99.5 || blocked, snapshot?.session?.resetsAt, tint.opacity(0.8))
    }
}
