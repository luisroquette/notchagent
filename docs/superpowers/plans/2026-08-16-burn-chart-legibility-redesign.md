# Burn Chart Legibility Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the burn chart's 4 model-identity lines actually distinguishable — validated color palette, direct end-of-line labels instead of a separate legend row, thicker alternate lines.

**Architecture:** Pure data change (Theme color constants) + pure testable label-collision math (mirrors the existing `BurnRate`/`ModelProjection` pattern of extracting non-UI logic into tested functions) + `Canvas` drawing changes in `BurnChartView`. No new data flow — `dominantModelShortName`/`alternates` params are unchanged from the prior feature.

**Tech Stack:** Swift 6, SwiftUI (`Canvas`), XCTest.

## Global Constraints

- Exact palette values (copied from the spec, `docs/superpowers/specs/2026-08-16-burn-chart-legibility-redesign-design.md`):
  - Haiku: dark `(0.224, 0.529, 0.898)`, light `(0.165, 0.471, 0.839)`
  - Sonnet: dark `(0.098, 0.620, 0.439)`, light `(0.106, 0.686, 0.478)`
  - Opus: dark `(0.565, 0.522, 0.914)`, light `(0.290, 0.227, 0.655)`
  - Fable: dark `(0.835, 0.318, 0.506)`, light `(0.910, 0.482, 0.643)`
- `Theme.coral` (the dominant-model highlight color) does not change.
- Text never carries a series color — only the small identity dot does. Labels stay in `Theme.textFaint`/`Theme.textDim`.
- The separate legend `HStack` row and its `legendDot` helper are removed entirely — replaced by direct end-of-line labels (per spec §2), not kept alongside them.
- The 660×430 panel size is not touched — this plan only rearranges content within it.
- Test command: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter <target>` (single target) or bare `swift test` (both `NotchAgentTests` and `AgentMeterCoreTests` — the full package). Build-only check: `swift build`.
- Run `git log --oneline --all -- <file>` before editing any file this plan touches.

---

## File Structure

| File | Change |
|---|---|
| `Sources/NotchAgent/Features/NotchOverlay/Components/Theme.swift` | Modify — replace the 4 model color RGB values |
| `Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift` | Modify — remove legend row/`legendDot`, add `nonCollidingLabelY` + end-of-line label drawing, bump alternate `lineWidth`, extend the "NOW" label |
| `Tests/NotchAgentTests/BurnChartLabelLayoutTests.swift` | Create — unit tests for `BurnChartView.nonCollidingLabelY` |
| `Sources/NotchAgent/Features/NotchOverlay/Views/NotchExpandedView.swift` | Modify — shorten the static caption string |

---

### Task 1: Validated color palette

**Files:**
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Components/Theme.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Theme.modelHaiku`/`modelSonnet`/`modelOpus`/`modelFable` return the new colors — same names, same call sites (`Theme.color(forModel:)`), only the RGB values change. No signature changes for any later task to consume.

No dedicated unit test — colors aren't meaningfully assertable via XCTest, matching every other `Theme` color in this file (none have tests). Verification is `swift build`.

- [ ] **Step 1: Replace the 4 color definitions**

In `Sources/NotchAgent/Features/NotchOverlay/Components/Theme.swift`, find:

```swift
    static let modelHaiku = dynamic(
        dark: NSColor(red: 0.42, green: 0.68, blue: 0.94, alpha: 1),
        light: NSColor(red: 0.15, green: 0.42, blue: 0.75, alpha: 1)
    )
    static let modelSonnet = dynamic(
        dark: NSColor(red: 0.35, green: 0.80, blue: 0.78, alpha: 1),
        light: NSColor(red: 0.10, green: 0.50, blue: 0.48, alpha: 1)
    )
    static let modelOpus = dynamic(
        dark: NSColor(red: 0.68, green: 0.56, blue: 0.94, alpha: 1),
        light: NSColor(red: 0.42, green: 0.28, blue: 0.72, alpha: 1)
    )
    static let modelFable = dynamic(
        dark: NSColor(red: 0.94, green: 0.52, blue: 0.72, alpha: 1),
        light: NSColor(red: 0.72, green: 0.20, blue: 0.46, alpha: 1)
    )
```

Replace with (comment explains why these specific values, for the next person who touches this file):

```swift
    // Re-picked 2026-08-16 after a live user report ("can't tell the
    // lines apart") turned out to be measurable: the original 4 colors
    // validated at worst-pair ΔE 12 (dataviz skill's contrast checker),
    // below the 15 floor for normal color vision. These validate at
    // worst-pair ΔE 16 (dark) / 19.7 (dark, normal-vision) alongside
    // Theme.coral. Before changing these again, re-run
    // `node scripts/validate_palette.js "<hex,hex,...>" --mode dark`
    // (and --mode light) from the dataviz skill directory — don't
    // eyeball it.
    static let modelHaiku = dynamic(
        dark: NSColor(red: 0.224, green: 0.529, blue: 0.898, alpha: 1),
        light: NSColor(red: 0.165, green: 0.471, blue: 0.839, alpha: 1)
    )
    static let modelSonnet = dynamic(
        dark: NSColor(red: 0.098, green: 0.620, blue: 0.439, alpha: 1),
        light: NSColor(red: 0.106, green: 0.686, blue: 0.478, alpha: 1)
    )
    static let modelOpus = dynamic(
        dark: NSColor(red: 0.565, green: 0.522, blue: 0.914, alpha: 1),
        light: NSColor(red: 0.290, green: 0.227, blue: 0.655, alpha: 1)
    )
    static let modelFable = dynamic(
        dark: NSColor(red: 0.835, green: 0.318, blue: 0.506, alpha: 1),
        light: NSColor(red: 0.910, green: 0.482, blue: 0.643, alpha: 1)
    )
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchAgent/Features/NotchOverlay/Components/Theme.swift
git commit -m "fix(theme): re-validate the burn chart's per-model colors

The original 4 colors were never run through a contrast checker.
Sonnet vs Haiku sat at ΔE 12 — below the 15 floor for normal color
vision, exactly matching a live report that the lines were
indistinguishable. New values validated (dataviz skill's
validate_palette.js) to worst-pair ΔE 16 dark / 19.7 dark
normal-vision, alongside the existing coral highlight.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Label-collision math (pure, tested)

**Files:**
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift`
- Test: `Tests/NotchAgentTests/BurnChartLabelLayoutTests.swift`

**Interfaces:**
- Consumes: nothing new (plain `CGFloat`/`[CGFloat]`).
- Produces: `static func BurnChartView.nonCollidingLabelY(_ y: CGFloat, avoiding placed: [CGFloat], minGap: CGFloat) -> CGFloat` — Task 3 calls this once per alternate line while drawing end-of-line labels, threading the growing `placed` array through the loop.

- [ ] **Step 1: Write the failing tests**

Create `Tests/NotchAgentTests/BurnChartLabelLayoutTests.swift`:

```swift
import XCTest
@testable import NotchAgent

final class BurnChartLabelLayoutTests: XCTestCase {
    func testFirstLabelIsNeverMoved() {
        let y = BurnChartView.nonCollidingLabelY(100, avoiding: [], minGap: 12)
        XCTAssertEqual(y, 100)
    }

    func testLabelFarFromExistingOnesIsNotMoved() {
        let y = BurnChartView.nonCollidingLabelY(200, avoiding: [100], minGap: 12)
        XCTAssertEqual(y, 200)
    }

    func testCollidingLabelIsPushedDownByExactlyOneGap() {
        let y = BurnChartView.nonCollidingLabelY(100, avoiding: [95], minGap: 12)
        XCTAssertEqual(y, 112)
    }

    func testCascadingCollisionPushesPastAllOccupiedSlots() {
        // 100 collides with 95 -> tries 112, which collides with 108 -> tries 124, clear.
        let y = BurnChartView.nonCollidingLabelY(100, avoiding: [95, 108], minGap: 12)
        XCTAssertEqual(y, 124)
    }

    func testExactBoundaryGapCountsAsClear() {
        // Exactly minGap apart is NOT a collision (< minGap is; == is fine).
        let y = BurnChartView.nonCollidingLabelY(112, avoiding: [100], minGap: 12)
        XCTAssertEqual(y, 112)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/BurnChartLabelLayoutTests`
Expected: FAIL with a compile error — `BurnChartView` has no member `nonCollidingLabelY`.

- [ ] **Step 3: Add the function**

In `Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift`, add this as a `static func` on `BurnChartView` (not `private` — the test target needs to call it), placed near the other geometry helpers (e.g. right after the `private var span: TimeInterval { ... }` line):

```swift
    /// Nudges `y` straight down in `minGap`-sized steps until it's at least
    /// `minGap` away from every value in `placed` — used to keep two
    /// alternate-line end labels from overlapping when their price ratios
    /// land them close together vertically. Pure and deterministic so it's
    /// unit-tested directly, unlike the rest of this file's Canvas drawing.
    static func nonCollidingLabelY(_ y: CGFloat, avoiding placed: [CGFloat], minGap: CGFloat) -> CGFloat {
        var candidate = y
        while placed.contains(where: { abs($0 - candidate) < minGap }) {
            candidate += minGap
        }
        return candidate
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/BurnChartLabelLayoutTests`
Expected: PASS — all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift Tests/NotchAgentTests/BurnChartLabelLayoutTests.swift
git commit -m "feat(burn-chart): add pure label-collision nudge function

nonCollidingLabelY pushes a candidate y-position down in fixed steps
until it clears every already-placed label — the one piece of new
drawing logic with real edge cases (2 close labels, cascading 3-way
collision), so it's pulled out of the Canvas closure and unit-tested,
matching how BurnRate/ModelProjection keep their math pure and tested.
Not yet called from the drawing code.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Wire it into the chart — end-of-line labels, drop the legend row, thicker lines

**Files:**
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift`
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Views/NotchExpandedView.swift`

**Interfaces:**
- Consumes: `BurnChartView.nonCollidingLabelY(_:avoiding:minGap:)` (Task 2), `Theme.color(forModel:)` / `Theme.modelHaiku` etc. (Task 1, values only — call sites unchanged), existing `alternates: [ModelProjection.Alternate]` / `dominantModelShortName: String?` params (unchanged from the prior feature).
- Produces: nothing new for later tasks — this is the last task in the plan.

No dedicated unit test (Canvas-drawn UI, consistent with this file's existing untested `polyline`/`interpolate`/`alternatePolyline`/`drawScrubber`). Verification is `swift build` + full test suite with zero regressions, plus a manual visual check.

- [ ] **Step 1: Remove the legend row and `legendDot`**

In `BurnChartView.swift`, `body` currently has:

```swift
            HStack {
                GaugeLabel(text: "START \(Format.time(windowStart))", color: Theme.textFaint, size: 8)
                Spacer()
                GaugeLabel(text: "RESET \(Format.time(windowEnd))", color: Theme.coralDim, size: 8)
            }
            if let dominantModelShortName, !alternates.isEmpty {
                HStack(spacing: 10) {
                    legendDot(color: Theme.coral, label: dominantModelShortName)
                    ForEach(alternates) { alternate in
                        legendDot(color: Theme.color(forModel: alternate.model), label: alternate.shortName)
                    }
                }
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            GaugeLabel(text: label.uppercased(), color: Theme.textFaint, size: 7)
        }
    }
```

Replace with (drops the `if let dominantModelShortName...` block and the now-unused `legendDot` function entirely — identity moves into the canvas drawing in Step 3 below):

```swift
            HStack {
                GaugeLabel(text: "START \(Format.time(windowStart))", color: Theme.textFaint, size: 8)
                Spacer()
                GaugeLabel(text: "RESET \(Format.time(windowEnd))", color: Theme.coralDim, size: 8)
            }
        }
    }
```

`dominantModelShortName` and `alternates` stay as `let` properties on the struct — Step 3 uses them inside `chart(in:)`.

- [ ] **Step 2: Verify it fails to build (confirms `legendDot`'s only caller is gone but the property is still referenced elsewhere, catching a scope mistake early)**

Run: `swift build 2>&1 | tail -20`
Expected: builds successfully (no more references to `legendDot` should remain after Step 1 — if the build fails here, you deleted something Step 3 still needs; re-check against the exact block above before proceeding).

- [ ] **Step 3: Bump alternate line width and add end-of-line labels**

Still in `BurnChartView.swift`, find the alternates drawing loop inside `chart(in:)`:

```swift
            for alternate in alternates {
                let points = alternatePolyline(alternate)
                guard points.count > 1 else { continue }
                var altPath = Path()
                altPath.move(to: CGPoint(x: x(points[0].0), y: y(points[0].1)))
                for point in points.dropFirst() {
                    altPath.addLine(to: CGPoint(x: x(point.0), y: y(point.1)))
                }
                context.stroke(
                    altPath,
                    with: .color(Theme.color(forModel: alternate.model)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 4])
                )
            }
```

Replace with:

```swift
            var placedLabelYs: [CGFloat] = []
            for alternate in alternates {
                let points = alternatePolyline(alternate)
                guard points.count > 1 else { continue }
                var altPath = Path()
                altPath.move(to: CGPoint(x: x(points[0].0), y: y(points[0].1)))
                for point in points.dropFirst() {
                    altPath.addLine(to: CGPoint(x: x(point.0), y: y(point.1)))
                }
                let color = Theme.color(forModel: alternate.model)
                context.stroke(
                    altPath,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4])
                )
                if let end = points.last {
                    let labelY = Self.nonCollidingLabelY(y(end.1), avoiding: placedLabelYs, minGap: 12)
                    placedLabelYs.append(labelY)
                    drawEndLabel(
                        context: context,
                        x: x(end.0), y: labelY,
                        text: alternate.shortName, color: color,
                        canvasWidth: canvasSize.width
                    )
                }
            }
```

Then add the `drawEndLabel` helper right after `drawScrubber` (near the bottom of the file, keeping the "MARK: Drawing" helpers together):

```swift
    /// A small colored identity dot + the model's name in neutral text —
    /// text never carries the series color, only the dot does (see
    /// dataviz skill's "text never wears the data color" rule). Clamped
    /// so a line ending near the right edge doesn't clip its label.
    private func drawEndLabel(
        context: GraphicsContext, x: CGFloat, y: CGFloat, text: String, color: Color, canvasWidth: CGFloat
    ) {
        let dotX = min(max(x + 6, 10), canvasWidth - 44)
        context.fill(
            Path(ellipseIn: CGRect(x: dotX - 2.5, y: y - 2.5, width: 5, height: 5)),
            with: .color(color)
        )
        context.draw(
            Text(text.uppercased()).font(Theme.label(7.5)).foregroundStyle(Theme.textFaint),
            at: CGPoint(x: dotX + 8, y: y),
            anchor: .leading
        )
    }
```

- [ ] **Step 4: Label the dominant line at the existing "NOW" marker**

Still in `chart(in:)`, find:

```swift
            context.draw(
                Text("NOW").font(Theme.label(7)).foregroundStyle(Theme.textDim),
                at: CGPoint(
                    x: min(max(nowPoint.x, 16), canvasSize.width - 16),
                    y: max(nowPoint.y - 13, 8)
                )
            )
```

Replace the `Text(...)` line only:

```swift
            context.draw(
                Text(dominantModelShortName.map { "NOW · \($0.uppercased())" } ?? "NOW")
                    .font(Theme.label(7)).foregroundStyle(Theme.textDim),
                at: CGPoint(
                    x: min(max(nowPoint.x, 16), canvasSize.width - 16),
                    y: max(nowPoint.y - 13, 8)
                )
            )
```

- [ ] **Step 5: Shorten the static caption**

In `Sources/NotchAgent/Features/NotchOverlay/Views/NotchExpandedView.swift`, find:

```swift
            GaugeLabel(
                text: "SOLID = REAL USAGE · DOTTED = PROJECTION AT CURRENT PACE",
                color: Theme.textFaint,
                size: 7
            )
```

Replace the `text:` value:

```swift
            GaugeLabel(
                text: "SOLID = REAL · DASHED = PROJECTED",
                color: Theme.textFaint,
                size: 7
            )
```

- [ ] **Step 6: Build and run the full suite**

Run: `swift build`
Expected: builds with no errors.

Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test`
Expected: PASS — zero failures, same count as before this task plus the 5 new tests from Task 2 (no new tests in this task).

- [ ] **Step 7: Manual visual check**

Build the app (`Scripts/make-app.sh` or the project's normal dev-run workflow), open the Burn page for the Claude provider with real recent activity, and confirm: no separate legend row under the chart; each alternate line ends in a small colored dot + its model name in neutral gray text; the "NOW" label reads e.g. "NOW · SONNET" when a dominant model is known; alternate lines are visibly thicker than before; the static caption below reads "SOLID = REAL · DASHED = PROJECTED".

- [ ] **Step 8: Commit**

```bash
git add Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift Sources/NotchAgent/Features/NotchOverlay/Views/NotchExpandedView.swift
git commit -m "feat(burn-chart): direct end-of-line labels replace the legend row

Drops the separate legend HStack and legendDot in favor of a small
colored identity dot + model name drawn right where each line ends —
frees ~20px of vertical space in the fixed 660x430 panel and puts the
identity read where the eye already is. The dominant/coral line's
identity moves into the existing NOW label ('NOW · SONNET') instead of
a new marker. Alternate lines go from 1px to the design system's 2px
line spec. Collision nudging via the Task 2 nonCollidingLabelY.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** §1 palette → Task 1. §2 end-of-line labels + anti-collision + dominant-line NOW label → Tasks 2–3. §3 shorter caption → Task 3 Step 5. §4 thicker lines → Task 3 Step 3. "Fora de escopo" items (panel resize, Codex, coral color) — not touched by any task, correctly absent.
- **Placeholder scan:** every step has literal code and exact values; no TBD/TODO; every test has real computed expected values.
- **Type consistency:** `BurnChartView.nonCollidingLabelY(_:avoiding:minGap:) -> CGFloat` (Task 2) is called with the exact same signature in Task 3 Step 3 (`Self.nonCollidingLabelY(y(end.1), avoiding: placedLabelYs, minGap: 12)`). `drawEndLabel`'s parameter list in Task 3 Step 3's call site matches its declaration in the same task's helper. `dominantModelShortName`/`alternates` properties are untouched from the prior feature — no signature drift.
