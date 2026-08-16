# Desk multi-model burn protocol — design

**Status:** Approved
**Repo:** luisroquette/notchagent (this repo)
**Companion spec:** `luisroquette/notchagent-desk` →
`docs/superpowers/specs/2026-08-16-desk-multi-model-burn-screen-design.md`
(firmware side, consumes the wire fields this spec defines)

## Goal

Extend the `DeskSnapshot` wire protocol and `DeskSnapshotFactory` so the
physical NotchAgent Desk can render the same multi-model burn projection
(Haiku/Sonnet/Opus/Fable alternates) already shipped in the macOS app's BURN
chart (v3.2.0), without duplicating the projection math.

## Background

The app already computes this via `ModelProjection.dominantModel(...)` and
`ModelProjection.alternates(...)` (`Sources/NotchAgent/Core/Services/
ModelProjection.swift`), consumed by `BurnChartView`. The Desk wire protocol
(`Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift`) already
carries a `burnHistory: [BurnPoint]` field (`ageSeconds`, `usedPercent`) for
the dominant/primary provider's real usage curve — populated by
`aggregateBurnHistory`, but currently unconsumed by the firmware (verified:
no `lv_chart`/`lv_line` draws it as of `notchagent-desk` commit `4f4242e`).

## Approach

Reuse `burnHistory` as the real series for the dominant model (finally
consuming it). Add only the data an embedded client needs to reconstruct the
other three lines by scaling that same series — not N separate point arrays:

```swift
extension DeskSnapshot {
    struct ModelAlternate: Codable, Sendable, Equatable {
        var shortName: String   // "Haiku","Sonnet","Opus","Fable" — matches
                                 // ModelProjection.shortName(for:)
        var priceRatio: Double  // alternate cost ÷ dominant cost, per token
    }
}
```

New fields on `DeskSnapshot`, both defaulted for backward compatibility
(older firmware ignores unknown JSON keys; older hosts never send them):

```swift
var dominantModelShortName: String? = nil
var modelAlternates: [DeskSnapshot.ModelAlternate] = []
```

`DeskSnapshotFactory.make(from:now:)` populates both from the exact same
calls `BurnChartView`'s call site already makes in `NotchExpandedView.swift`
(`ModelProjection.dominantModel`, `ModelProjection.alternates`) — no new
projection logic, just wiring existing pure functions into the Desk snapshot
path. `modelAlternates` stays empty when there's no session data yet (mirrors
the app's own empty-state) or when `dominantModelShortName` is nil.

The firmware derives each alternate's line by, for every `BurnPoint` in
`burnHistory`, computing `min(100, usedPercent * priceRatio)` — identical to
`BurnChartView.alternatePolyline`'s scale-and-cap rule. This keeps the wire
payload at O(alternates) instead of O(alternates × history points).

### Protocol version

`PROTOCOL_VERSION` (in `notchagent-desk`) goes `1.1` → `1.2`: purely additive
fields, no existing field changes — a MINOR bump per that repo's
`VERSIONING.md` ("same MAJOR, newer protocol MINOR: additive fields ... must
be ignored safely by older compatible hosts").

## Data flow

```
ModelProjection.dominantModel/alternates (existing, pure, tested)
        │
        ▼
DeskSnapshotFactory.make  ──▶  DeskSnapshot.dominantModelShortName
        │                      DeskSnapshot.modelAlternates
        ▼
   USB JSON frame  ──▶  firmware parses shortName + priceRatio
                         firmware scales existing burnHistory points
                         firmware draws 4 lines (this repo's job ends here)
```

## Error handling

- No session data yet / `dominantModel` returns `nil`: `dominantModelShortName`
  is `nil`, `modelAlternates` is `[]`. Firmware's cold-start state (defined
  in the companion firmware spec) already needs to handle an empty
  `burnHistory` today — this is not a new empty case.
- A `priceRatio` can never be negative or zero (pricing table entries are
  fixed positive constants); no clamping needed on the app side beyond what
  `ModelProjection.alternates` already guarantees.

## Testing

- `Tests/NotchAgentTests/NotchAgentDeskTests.swift` (existing file, covers
  `DeskSnapshotFactory`): assert `dominantModelShortName`/`modelAlternates` match
  `ModelProjection.dominantModel`/`.alternates` for a fixture `UsageStore`
  with known per-model token spend, and assert both are empty when
  `modelTokens` is absent.
- Existing `ModelProjectionTests` are unchanged — no new projection logic is
  introduced by this spec.

## Out of scope (covered by the companion firmware spec)

- Rendering the lines, colors, labels, or cold-start UI on the physical
  display.
- Any change to the BURN screen layout.
