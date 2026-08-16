# Desk Multi-Model Burn Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `DeskSnapshot` and `DeskSnapshotFactory` so the physical
Desk can reconstruct the app's multi-model burn projection from the wire,
without duplicating `ModelProjection`'s math.

**Architecture:** Two additive `DeskSnapshot` fields
(`dominantModelShortName: String?`, `modelAlternates:
[DeskSnapshot.ModelAlternate]`) populated in `DeskSnapshotFactory.make` from
the same `ModelProjection.dominantModel`/`.alternates` calls
`NotchExpandedView.burnPage` already makes. `burnHistory` (existing field)
stays the dominant model's real series; firmware scales it per alternate.

**Tech Stack:** Swift 6, SwiftPM, XCTest.

## Global Constraints

- Both new fields default to `nil`/`[]` — decoding a snapshot written before
  this change must not throw (mirrors the existing `usedPercentIsFromQuota`
  pattern in `SessionUsage`).
- No new projection logic. `ModelProjection.dominantModel`/`.alternates`/
  `.shortName(for:)` are the only source of the numbers — this plan only
  wires them into the Desk snapshot path.
- Reuses the exact same `usedPercentIsFromQuota` gate `NotchExpandedView
  .burnPage` uses (`session?.usedPercentIsFromQuota == true`) — a
  dollar-scaled alternate line is meaningless if `usedPercent` itself isn't
  quota-backed.
- The dominant-model/alternates computation is scoped to the **primary**
  provider, matching `aggregateBurnHistory`'s existing primary-provider
  scoping (Desk shows one burn chart, not one per provider).
- Protocol version: `NotchAgentDeskProtocol.protocolMinor` goes `1` → `2`
  (this repo's copy; the firmware repo's `PROTOCOL_VERSION` file is bumped
  by the companion plan there).

---

### Task 1: `DeskSnapshot.ModelAlternate` + the two new fields

**Files:**
- Modify: `Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift`
- Test: `Tests/NotchAgentTests/NotchAgentDeskTests.swift`

**Interfaces:**
- Produces: `DeskSnapshot.ModelAlternate { shortName: String, priceRatio:
  Double }` (Codable, Sendable, Equatable), `DeskSnapshot
  .dominantModelShortName: String?`, `DeskSnapshot.modelAlternates:
  [DeskSnapshot.ModelAlternate]`. Task 2 populates these; this task only
  defines them and proves they decode safely.

- [ ] **Step 1: Add the nested struct and the two fields**

In `NotchAgentDeskProtocol.swift`, inside `struct DeskSnapshot`, add the
nested type next to the existing `Model` struct (around line 98-103):

```swift
    struct ModelAlternate: Codable, Sendable, Equatable {
        /// "Haiku"/"Sonnet"/"Opus"/"Fable" — matches ModelProjection.shortName(for:).
        var shortName: String
        /// costUSD(alternate, sessionTokens) / costUSD(dominant, sessionTokens).
        /// Firmware multiplies each burnHistory.usedPercent by this and clamps
        /// to 100 to draw the alternate's line — see ModelProjection.Alternate.
        var priceRatio: Double
    }
```

Then add the two properties to `DeskSnapshot` itself, right after `models:
[Model]` (around line 114):

```swift
    var models: [Model]
    var dominantModelShortName: String? = nil
    var modelAlternates: [ModelAlternate] = []
```

- [ ] **Step 2: Bump the protocol minor version**

In the same file, change line 6:

```swift
    static let protocolMinor: UInt8 = 2
```

- [ ] **Step 3: Write the backward-compatibility decode test**

Add to `NotchAgentDeskTests.swift`, near the other `DeskSnapshot` tests:

```swift
    func testDeskSnapshotDecodesWithoutModelAlternateFields() throws {
        // A payload written before dominantModelShortName/modelAlternates
        // existed — must not throw, matching the SessionUsage precedent.
        let json = """
        {
            "product": "NotchAgent",
            "protocolMajor": 1,
            "protocolMinor": 1,
            "generatedAt": 0,
            "overallAttention": "ok",
            "isPaused": false,
            "providers": [],
            "burnHistory": [],
            "rhythm": [],
            "models": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(DeskSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.dominantModelShortName)
        XCTAssertEqual(snapshot.modelAlternates, [])
    }
```

`.millisecondsSince1970` matches the production encode/decode pair in
`NotchAgentDeskBridge.swift:299-306` — the actual wire path for
`DeskSnapshot` — so `generatedAt: 0` above decodes without error.

- [ ] **Step 4: Run the test, verify it passes**

Run: `swift test --filter NotchAgentDeskTests`
Expected: PASS, including the new test.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift Tests/NotchAgentTests/NotchAgentDeskTests.swift
git commit -m "feat(desk-protocol): add dominantModelShortName and modelAlternates fields"
```

---

### Task 2: Wire `DeskSnapshotFactory.make` to populate the new fields

**Files:**
- Modify: `Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift`
- Test: `Tests/NotchAgentTests/NotchAgentDeskTests.swift`

**Interfaces:**
- Consumes: `ModelProjection.dominantModel(modelTokens: [String:
  TokenUsage]) -> String?`, `ModelProjection.alternates(dominantModel:
  String, sessionTokens: TokenUsage) -> [ModelProjection.Alternate]`
  (`Alternate.shortName: String`, `.priceRatio: Double`),
  `ModelProjection.shortName(for: String) -> String` — all in
  `Sources/NotchAgent/Core/Services/ModelProjection.swift`, unchanged by
  this task. `SessionUsage.usedPercentIsFromQuota: Bool?`, `.modelTokens:
  [String: TokenUsage]?`, `.tokens: TokenUsage` — in
  `Sources/NotchAgent/Core/Models/Usage.swift`, unchanged.
- Produces: `DeskSnapshot.dominantModelShortName`/`.modelAlternates` now
  carry real data for any snapshot built after this task.

- [ ] **Step 1: Write the failing tests**

Add to `NotchAgentDeskTests.swift`, next to
`testBurnHistoryUsesPrimaryProviderAndBoundsValues` (uses the same fixture
style — see that test for the `UsageStore`/`defaults` setup pattern):

```swift
    @MainActor
    func testDominantModelAndAlternatesPopulatedFromPrimaryProviderSession() {
        let suite = "NotchAgentDeskTests.ModelAlternates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(preferences: PreferencesStore(defaults: defaults))
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            capturedAt: now,
            health: .ok,
            session: SessionUsage(
                tokens: TokenUsage(input: 1_000, output: 500),
                usedPercent: 40,
                modelTokens: [
                    "claude-sonnet-5": TokenUsage(input: 900, output: 450),
                    "claude-haiku-4-5-20251001": TokenUsage(input: 100, output: 50),
                ],
                usedPercentIsFromQuota: true
            ),
            lastActivityAt: now
        ))

        let snapshot = DeskSnapshotFactory.make(from: store, now: now)
        XCTAssertEqual(snapshot.dominantModelShortName, "Sonnet")
        XCTAssertEqual(Set(snapshot.modelAlternates.map(\.shortName)), ["Haiku", "Opus", "Fable"])
        XCTAssertTrue(snapshot.modelAlternates.allSatisfy { $0.priceRatio > 0 })
    }

    @MainActor
    func testDominantModelIsNilWhenUsedPercentIsNotQuotaBacked() {
        let suite = "NotchAgentDeskTests.ModelAlternates.NotQuota.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(preferences: PreferencesStore(defaults: defaults))
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        store.apply(UsageSnapshot(
            provider: .claudeCode,
            capturedAt: now,
            health: .ok,
            session: SessionUsage(
                tokens: TokenUsage(input: 1_000, output: 500),
                usedPercent: 40,
                modelTokens: ["claude-sonnet-5": TokenUsage(input: 900, output: 450)],
                usedPercentIsFromQuota: false
            ),
            lastActivityAt: now
        ))

        let snapshot = DeskSnapshotFactory.make(from: store, now: now)
        XCTAssertNil(snapshot.dominantModelShortName)
        XCTAssertEqual(snapshot.modelAlternates, [])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter NotchAgentDeskTests`
Expected: FAIL — `dominantModelShortName`/`modelAlternates` are still
always `nil`/`[]` from Task 1's defaults.

- [ ] **Step 3: Implement**

In `NotchAgentDeskProtocol.swift`'s `DeskSnapshotFactory.make(from:now:)`,
after the existing `let models = aggregateModels(...)` line and before the
`return DeskSnapshot(...)` call, add:

```swift
        let (dominantModelShortName, modelAlternates) = modelBurnAlternates(store: store)
```

Then add `dominantModelShortName: dominantModelShortName,
modelAlternates: modelAlternates,` to the `DeskSnapshot(...)` initializer
call, in the same position as the struct's property order (right after
`models: models,`).

Add the new private static helper next to `aggregateBurnHistory` (same
primary-provider resolution pattern — read that function first, this
mirrors its guard shape):

```swift
    @MainActor
    private static func modelBurnAlternates(
        store: UsageStore
    ) -> (dominantModelShortName: String?, modelAlternates: [DeskSnapshot.ModelAlternate]) {
        guard let primary = store.primaryProvider,
              let session = store.snapshots[primary]?.session,
              session.usedPercentIsFromQuota == true,
              let modelTokens = session.modelTokens,
              let dominant = ModelProjection.dominantModel(modelTokens: modelTokens)
        else { return (nil, []) }

        let alternates = ModelProjection.alternates(dominantModel: dominant, sessionTokens: session.tokens)
            .map { DeskSnapshot.ModelAlternate(shortName: $0.shortName, priceRatio: $0.priceRatio) }
        return (ModelProjection.shortName(for: dominant), alternates)
    }
```

Note: `ModelProjection.alternates` is not `public` (internal) — this
compiles because `DeskSnapshotFactory` is in the same `NotchAgent` target,
exactly like `NotchExpandedView.burnPage`'s existing call to the same
function.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter NotchAgentDeskTests`
Expected: PASS, all `NotchAgentDeskTests` green, including the two new
tests and the existing `testBurnHistoryUsesPrimaryProviderAndBoundsValues`
(unchanged behavior for that field).

- [ ] **Step 5: Run the full suite**

Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test`
Expected: 0 failures, count is the prior total (281) + 3 new tests = 284.

- [ ] **Step 6: Commit**

```bash
git add Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift Tests/NotchAgentTests/NotchAgentDeskTests.swift
git commit -m "feat(desk-protocol): wire DeskSnapshotFactory to ModelProjection for Desk alternates"
```

---

## Self-Review

- **Spec coverage:** covers every requirement in
  `2026-08-16-desk-multi-model-burn-protocol-design.md` — the new struct,
  the two fields, the factory wiring, the backward-compat test, the
  protocol minor bump. The spec's "out of scope" (firmware rendering) has
  no task here, correctly.
- **Placeholder scan:** none — every step has real code, real file paths,
  real test bodies.
- **Type consistency:** `DeskSnapshot.ModelAlternate.shortName`/
  `.priceRatio` names match what the companion firmware spec's field names
  assume (`shortName`, `priceRatio`) — verified against
  `2026-08-16-desk-multi-model-burn-screen-design.md` in the
  `notchagent-desk` repo.

## After this plan lands

Version bump (`VERSION` 3.2.0 → 3.3.0, `Info.plist`, `README.md`,
`CHANGELOG.md`) happens as a release step after the final review, same
process as the 3.2.0 release — not a task in this plan.
