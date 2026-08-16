# Burn Chart Multi-Model Projection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 3 dashed alternate-model lines to the Claude burn chart, showing what the current session's quota burn would look like under Haiku/Sonnet/Opus/Fable pricing, with the model that actually burned the most tokens this window kept as the existing solid+dashed highlighted line.

**Architecture:** No new metric — reuses the existing `% USED` axis. A new `SessionUsage.modelTokens: [String: TokenUsage]` field (populated by a new parser-level `hourlyByModel` aggregation) identifies the dominant model. A new pure `ModelProjection` enum (mirroring `BurnRate`) computes a price ratio per alternate model from `PricingTable`. `BurnChartView` scales its existing real-usage polyline by that ratio to draw each alternate line — no separate cost time series.

**Tech Stack:** Swift 6, SwiftUI (`Canvas`), XCTest. Package: `NotchAgent` (target `NotchAgent`, tests `NotchAgentTests`).

## Global Constraints

- Follow existing file patterns exactly — `BurnRate.swift` is the template for `ModelProjection.swift` (pure functions, fully unit-tested, `Sendable`/`Equatable` structs).
- Never fabricate a cost for a model `PricingTable` doesn't know — a `nil` from `PricingTable.costUSD` means "omit this line," never "treat as $0" (established project rule — see `PricingTests.testUnknownModelCostIsNilNotZero`).
- Test command: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test` (full suite) or `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter <Target>/<TestClass>/<testMethod>` (single test). Build-only check: `swift build`.
- Run `git log --oneline --all -- <file>` before editing any file touched by this plan — a fix may already exist on another branch (project has a documented history of duplicated fixes from missing this check).
- Codex replica (GPT 5.6 Sol/Terra/Luna) is explicitly out of scope — do not touch `PricingTable`'s `gpt-*` entries or Codex provider files in this plan.

---

## File Structure

| File | Change |
|---|---|
| `Sources/NotchAgent/Features/Providers/Shared/PricingTable.swift` | Modify — add `claude-opus-5` / `claude-fable-5` entries |
| `Tests/NotchAgentTests/AggregatorAndFormatTests.swift` | Modify — regression test in `PricingTests` |
| `Sources/NotchAgent/Features/Providers/Claude/ClaudeTranscriptParser.swift` | Modify — add `ClaudeFileStat.hourlyByModel` |
| `Tests/NotchAgentTests/ClaudeParserTests.swift` | Modify — new test for `hourlyByModel` |
| `Sources/NotchAgent/Features/Providers/Claude/ClaudeProvider.swift` | Modify — merge `hourlyByModel`, add `sumBucketsByModel`, populate `SessionUsage.modelTokens` |
| `Sources/NotchAgent/Core/Models/Usage.swift` | Modify — add `SessionUsage.modelTokens` field |
| `Tests/NotchAgentTests/ProviderIntegrationTests.swift` | Modify — new end-to-end test |
| `Sources/NotchAgent/Core/Services/ModelProjection.swift` | Create — pure dominant-model + price-ratio calculator |
| `Tests/NotchAgentTests/ModelProjectionTests.swift` | Create — unit tests for the above |
| `Sources/NotchAgent/Features/NotchOverlay/Components/Theme.swift` | Modify — 4 fixed per-model colors + `Theme.color(forModel:)` |
| `Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift` | Modify — new params, `alternatePolyline`, draw loop, legend |
| `Sources/NotchAgent/Features/NotchOverlay/Views/NotchExpandedView.swift` | Modify — wire `dominantModel`/`alternates` into the `BurnChartView(...)` call site |

---

### Task 1: Fix `PricingTable` — Opus 5 / Fable 5 pricing collision

**Files:**
- Modify: `Sources/NotchAgent/Features/Providers/Shared/PricingTable.swift`
- Test: `Tests/NotchAgentTests/AggregatorAndFormatTests.swift`

**Interfaces:**
- Consumes: nothing new (existing `PricingTable.costUSD(model:usage:) -> Double?`).
- Produces: `PricingTable.costUSD(model: "claude-opus-5", ...)` and `PricingTable.costUSD(model: "claude-fable-5", ...)` now return distinct values instead of both falling through to the old generic `"claude-opus"`/`"claude-fable"` catch-all (`15/75/18.75/1.5`).

- [ ] **Step 1: Write the failing regression test**

  In `Tests/NotchAgentTests/AggregatorAndFormatTests.swift`, inside the existing `final class PricingTests: XCTestCase { ... }` block (it already contains `testPrefixMatching`, `testClaudeCostMath`, `testUnknownModelCostIsNilNotZero`), add:

  ```swift
      // REGRESSÃO: Opus 5 e Fable 5 caíam no mesmo catch-all antigo (15/75)
      // e saíam com custo idêntico — Fable é mais caro que Opus na tabela
      // oficial (achado 15/08/2026, ver
      // docs/superpowers/specs/2026-08-15-burn-chart-multi-model-projection-design.md).
      func testOpus5AndFable5HaveDistinctCurrentPricing() throws {
          let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
          let opusCost = try XCTUnwrap(PricingTable.costUSD(model: "claude-opus-5", usage: usage))
          let fableCost = try XCTUnwrap(PricingTable.costUSD(model: "claude-fable-5", usage: usage))
          XCTAssertEqual(opusCost, 30, accuracy: 0.001) // 5 + 25 per MTok
          XCTAssertEqual(fableCost, 60, accuracy: 0.001) // 10 + 50 per MTok
          XCTAssertGreaterThan(fableCost, opusCost)
      }
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/PricingTests/testOpus5AndFable5HaveDistinctCurrentPricing`
  Expected: FAIL — `opusCost` and `fableCost` are both `45.0` (the old shared `15/75` catch-all), so `XCTAssertEqual(opusCost, 30, ...)` fails.

- [ ] **Step 3: Add the specific pricing entries**

  In `Sources/NotchAgent/Features/Providers/Shared/PricingTable.swift`, the `entries` array currently starts:

  ```swift
      static let entries: [(prefix: String, pricing: ModelPricing)] = [
          ("claude-fable", ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
          ("claude-opus", ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
  ```

  Insert two new entries **before** those two (longest-prefix-first — `entries.first { model.hasPrefix($0.prefix) }` picks the first match, so the specific IDs must come first):

  ```swift
      static let entries: [(prefix: String, pricing: ModelPricing)] = [
          ("claude-opus-5", ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)),
          ("claude-fable-5", ModelPricing(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1.0)),
          ("claude-fable", ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
          ("claude-opus", ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
  ```

  (The two original lines stay unchanged, right after, as the fallback for older Opus/Fable snapshot IDs that don't match the `-5` suffix.)

- [ ] **Step 4: Run test to verify it passes**

  Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/PricingTests`
  Expected: PASS — all `PricingTests` tests green, including the new one.

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/NotchAgent/Features/Providers/Shared/PricingTable.swift Tests/NotchAgentTests/AggregatorAndFormatTests.swift
  git commit -m "fix(pricing): give Opus 5 and Fable 5 their own PricingTable entries

  Both fell through to the same generic pre-Opus-5 catch-all (15/75),
  making Fable read as equal-cost to Opus when it's actually pricier
  (\$10/\$50 vs \$5/\$25 per MTok). Adds specific entries ahead of the
  generic ones; older Opus/Fable snapshot IDs still fall back to the
  original catch-all unchanged.

  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
  ```

---

### Task 2: Track per-model tokens per hour bucket in the transcript parser

**Files:**
- Modify: `Sources/NotchAgent/Features/Providers/Claude/ClaudeTranscriptParser.swift`
- Test: `Tests/NotchAgentTests/ClaudeParserTests.swift`

**Interfaces:**
- Consumes: existing `TokenUsage` (`Sources/NotchAgent/Core/Models/Usage.swift`).
- Produces: `ClaudeFileStat.hourlyByModel: [Date: [String: TokenUsage]]` — for each hour bucket, tokens per model seen in that hour. Task 3 merges this across files and filters it to the 5h session window.

- [ ] **Step 1: Write the failing test**

  In `Tests/NotchAgentTests/ClaudeParserTests.swift`, inside `final class ClaudeParserTests: XCTestCase { ... }`, add (after `testAggregatesIntoHourBuckets`):

  ```swift
      func testAggregatesHourlyByModel() throws {
          let stat = try ClaudeTranscriptParser.parseFile(at: fixtureURL).stat
          let hour14 = Timestamps.parseISO8601("2026-07-10T14:00:00Z")!
          let byModel = try XCTUnwrap(stat.hourlyByModel[hour14])
          XCTAssertEqual(byModel["claude-fable-5"], TokenUsage(input: 100, output: 200, cacheWrite: 1000, cacheRead: 5000))
          XCTAssertEqual(byModel["claude-sonnet-5"], TokenUsage(input: 50, output: 75, cacheWrite: 0, cacheRead: 0))
      }
  ```

  (This relies on the existing fixture `Tests/NotchAgentTests/Fixtures/claude-session.jsonl`, already used by `testAggregatesIntoHourBuckets` in the same file: hour `2026-07-10T14:00:00Z` has one deduplicated `claude-fable-5` line at 14:05/14:06 — `req_1`, only the first of the two duplicate-`requestId` lines counts — with `input:100, output:200, cache_creation_input_tokens:1000, cache_read_input_tokens:5000`, plus one `claude-sonnet-5` line at 14:40 with `input:50, output:75`.)

- [ ] **Step 2: Run test to verify it fails**

  Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/ClaudeParserTests/testAggregatesHourlyByModel`
  Expected: FAIL with a compile error — `ClaudeFileStat` has no member `hourlyByModel`.

- [ ] **Step 3: Add `hourlyByModel` to `ClaudeFileStat` and populate it**

  In `Sources/NotchAgent/Features/Providers/Claude/ClaudeTranscriptParser.swift`, `ClaudeFileStat` currently declares:

  ```swift
      var hours: [Date: HourStat] = [:]
      var byModel: [String: ModelStat] = [:]
  ```

  Add a third dictionary right after `byModel`:

  ```swift
      var hours: [Date: HourStat] = [:]
      var byModel: [String: ModelStat] = [:]
      /// Same tokens as `hours`/`byModel`, but keyed by both dimensions at
      /// once — the only shape that can answer "what did each model burn
      /// inside this specific hour" (needed to scope per-model usage to the
      /// 5h session window, not just the whole lookback).
      var hourlyByModel: [Date: [String: TokenUsage]] = [:]
  ```

  Then in `parseFile(at:from:into:)`, right after the existing block that updates `stat.byModel[model]` (currently):

  ```swift
              var modelStat = stat.byModel[model] ?? .init()
              modelStat.tokens += tokens
              modelStat.costUSD += cost
              stat.byModel[model] = modelStat
  ```

  add:

  ```swift
              var byHourModel = stat.hourlyByModel[hour] ?? [:]
              byHourModel[model, default: .zero] += tokens
              stat.hourlyByModel[hour] = byHourModel
  ```

  (`hour` is already in scope two lines above from `let hour = timestamp.flooredToHour`.)

- [ ] **Step 4: Run test to verify it passes**

  Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/ClaudeParserTests`
  Expected: PASS — all `ClaudeParserTests` tests green, including the new one.

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/NotchAgent/Features/Providers/Claude/ClaudeTranscriptParser.swift Tests/NotchAgentTests/ClaudeParserTests.swift
  git commit -m "feat(claude-parser): track token usage per model per hour bucket

  hours/byModel already exist but each collapses one dimension the
  other needs — hourlyByModel keeps both, so a caller can later filter
  to an arbitrary time window and still know per-model tokens inside
  it (needed for burn-chart multi-model projection).

  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
  ```

---

### Task 3: Populate `SessionUsage.modelTokens` scoped to the 5h window

**Files:**
- Modify: `Sources/NotchAgent/Core/Models/Usage.swift`
- Modify: `Sources/NotchAgent/Features/Providers/Claude/ClaudeProvider.swift`
- Test: `Tests/NotchAgentTests/ProviderIntegrationTests.swift`

**Interfaces:**
- Consumes: `ClaudeFileStat.hourlyByModel` (Task 2).
- Produces: `SessionUsage.modelTokens: [String: TokenUsage]?` — per-model tokens inside the current 5h session window only. Task 4 (`ModelProjection`) and Task 6 (`BurnChartView` wiring) consume this via `snapshot.session?.modelTokens`.

- [ ] **Step 1: Write the failing test**

  In `Tests/NotchAgentTests/ProviderIntegrationTests.swift`, inside `final class ProviderIntegrationTests: XCTestCase { ... }`, add a new test right after `testClaudeProviderEndToEnd`:

  ```swift
      func testClaudeProviderTracksPerModelTokensWithinSessionWindow() async throws {
          let projectDir = root.appendingPathComponent("projects/-Users-test", isDirectory: true)
          try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

          let now = Date()
          func line(_ date: Date, id: String, model: String, input: Int, output: Int) -> String {
              """
              {"type":"assistant","timestamp":"\(iso(date))","requestId":"\(id)","message":{"id":"m_\(id)","model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
              """
          }
          let content = [
              line(now.addingTimeInterval(-90 * 60), id: "a", model: "claude-sonnet-5", input: 100, output: 400),
              line(now.addingTimeInterval(-30 * 60), id: "b", model: "claude-haiku-4-5-20251001", input: 50, output: 250),
              // Outside the 5h window entirely — must not leak into modelTokens.
              line(now.addingTimeInterval(-3 * 86_400), id: "c", model: "claude-opus-5", input: 1000, output: 2000),
          ].joined(separator: "\n") + "\n"
          try Data(content.utf8).write(to: projectDir.appendingPathComponent("session.jsonl"))

          let provider = ClaudeProvider(root: root.appendingPathComponent("projects"), probe: nil)
          let snapshot = try await provider.fetchSnapshot(settings: AppSettings())

          let modelTokens = try XCTUnwrap(snapshot.session?.modelTokens)
          XCTAssertEqual(modelTokens["claude-sonnet-5"]?.total, 500)
          XCTAssertEqual(modelTokens["claude-haiku-4-5-20251001"]?.total, 300)
          XCTAssertNil(modelTokens["claude-opus-5"], "3-day-old activity is outside the 5h session window")
      }
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/ProviderIntegrationTests/testClaudeProviderTracksPerModelTokensWithinSessionWindow`
  Expected: FAIL with a compile error — `SessionUsage` has no member `modelTokens`.

- [ ] **Step 3: Add `modelTokens` to `SessionUsage`**

  In `Sources/NotchAgent/Core/Models/Usage.swift`, `SessionUsage` currently is:

  ```swift
  public struct SessionUsage: Codable, Sendable, Equatable {
      public var tokens: TokenUsage
      public var cost: CostEstimate?
      public var startedAt: Date?
      public var resetsAt: Date?
      /// 0–100. nil when the provider exposes no session limit locally.
      public var usedPercent: Double?
      /// Other scopes sharing this window (e.g. a model with its own separate
      /// cap) — never shown as the headline number, only in per-model detail.
      public var namedQuotas: [NamedQuota]?

      public init(
          tokens: TokenUsage = .zero,
          cost: CostEstimate? = nil,
          startedAt: Date? = nil,
          resetsAt: Date? = nil,
          usedPercent: Double? = nil,
          namedQuotas: [NamedQuota]? = nil
      ) {
          self.tokens = tokens
          self.cost = cost
          self.startedAt = startedAt
          self.resetsAt = resetsAt
          self.usedPercent = usedPercent
          self.namedQuotas = namedQuotas
      }
  }
  ```

  Replace it with:

  ```swift
  public struct SessionUsage: Codable, Sendable, Equatable {
      public var tokens: TokenUsage
      public var cost: CostEstimate?
      public var startedAt: Date?
      public var resetsAt: Date?
      /// 0–100. nil when the provider exposes no session limit locally.
      public var usedPercent: Double?
      /// Other scopes sharing this window (e.g. a model with its own separate
      /// cap) — never shown as the headline number, only in per-model detail.
      public var namedQuotas: [NamedQuota]?
      /// Token usage broken down by model, scoped to this session window —
      /// the only data granular enough to answer "what would this session
      /// have cost under a different model?" (`UsageSnapshot.modelBreakdown`
      /// is a flat total over the whole 8-day lookback, not this window).
      public var modelTokens: [String: TokenUsage]?

      public init(
          tokens: TokenUsage = .zero,
          cost: CostEstimate? = nil,
          startedAt: Date? = nil,
          resetsAt: Date? = nil,
          usedPercent: Double? = nil,
          namedQuotas: [NamedQuota]? = nil,
          modelTokens: [String: TokenUsage]? = nil
      ) {
          self.tokens = tokens
          self.cost = cost
          self.startedAt = startedAt
          self.resetsAt = resetsAt
          self.usedPercent = usedPercent
          self.namedQuotas = namedQuotas
          self.modelTokens = modelTokens
      }
  }
  ```

- [ ] **Step 4: Merge `hourlyByModel` across files and add `sumBucketsByModel`**

  In `Sources/NotchAgent/Features/Providers/Claude/ClaudeProvider.swift`, find the file-processing loop (`for url in files { ... }`) that currently merges `stat.hours` into `merged` and `stat.byModel` into `mergedModels`:

  ```swift
          var merged: [Date: ClaudeFileStat.HourStat] = [:]
          var mergedModels: [String: ClaudeFileStat.ModelStat] = [:]
          var lastActivity: Date?
          var lastModel: String?
          var failedFiles = 0
  ```

  Add a third accumulator:

  ```swift
          var merged: [Date: ClaudeFileStat.HourStat] = [:]
          var mergedModels: [String: ClaudeFileStat.ModelStat] = [:]
          var mergedHourlyByModel: [Date: [String: TokenUsage]] = [:]
          var lastActivity: Date?
          var lastModel: String?
          var failedFiles = 0
  ```

  Then right after the existing block that merges `stat.byModel` into `mergedModels`:

  ```swift
              for (model, modelStat) in stat.byModel {
                  var existing = mergedModels[model] ?? .init()
                  existing.tokens += modelStat.tokens
                  existing.costUSD += modelStat.costUSD
                  mergedModels[model] = existing
              }
  ```

  add:

  ```swift
              for (hour, byModel) in stat.hourlyByModel {
                  var existing = mergedHourlyByModel[hour] ?? [:]
                  for (model, tokens) in byModel {
                      existing[model, default: .zero] += tokens
                  }
                  mergedHourlyByModel[hour] = existing
              }
  ```

  Then add a new static function next to the existing `sumBuckets(_:from:to:)` (near the bottom of the file, right after it):

  ```swift
      /// Same windowing as `sumBuckets`, but keyed by model — the source for
      /// `SessionUsage.modelTokens`.
      static func sumBucketsByModel(
          _ merged: [Date: [String: TokenUsage]],
          from start: Date,
          to end: Date
      ) -> [String: TokenUsage] {
          var result: [String: TokenUsage] = [:]
          let flooredStart = start.flooredToHour
          for (hour, byModel) in merged where hour >= flooredStart && hour < end {
              for (model, tokens) in byModel {
                  result[model, default: .zero] += tokens
              }
          }
          return result
      }
  ```

- [ ] **Step 5: Populate `modelTokens` when building the session**

  In the same file, find where `session` is built:

  ```swift
          if let window = sessionWindow {
              let (tokens, cost) = Self.sumBuckets(merged, from: window.start, to: window.end)
              session = SessionUsage(
                  tokens: tokens,
                  cost: CostEstimate(amountUSD: cost),
                  startedAt: window.start,
                  resetsAt: window.end,
                  usedPercent: quota?.sessionPercent
                      ?? settings.claudeSessionTokenBudget.map { budget in
                          min(100, Double(tokens.total) / Double(max(budget, 1)) * 100)
                      },
                  namedQuotas: namedFable(fable?.sessionPercent, resetsAt: fable?.sessionResetsAt)
              )
          }
  ```

  Add `modelTokens:` as the last argument:

  ```swift
          if let window = sessionWindow {
              let (tokens, cost) = Self.sumBuckets(merged, from: window.start, to: window.end)
              session = SessionUsage(
                  tokens: tokens,
                  cost: CostEstimate(amountUSD: cost),
                  startedAt: window.start,
                  resetsAt: window.end,
                  usedPercent: quota?.sessionPercent
                      ?? settings.claudeSessionTokenBudget.map { budget in
                          min(100, Double(tokens.total) / Double(max(budget, 1)) * 100)
                      },
                  namedQuotas: namedFable(fable?.sessionPercent, resetsAt: fable?.sessionResetsAt),
                  modelTokens: Self.sumBucketsByModel(mergedHourlyByModel, from: window.start, to: window.end)
              )
          }
  ```

- [ ] **Step 6: Run test to verify it passes**

  Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/ProviderIntegrationTests`
  Expected: PASS — all `ProviderIntegrationTests` tests green, including the new one and the pre-existing `testClaudeProviderEndToEnd` (unaffected — it doesn't assert on `modelTokens`).

- [ ] **Step 7: Commit**

  ```bash
  git add Sources/NotchAgent/Core/Models/Usage.swift Sources/NotchAgent/Features/Providers/Claude/ClaudeProvider.swift Tests/NotchAgentTests/ProviderIntegrationTests.swift
  git commit -m "feat(claude-provider): scope per-model token usage to the 5h session window

  New SessionUsage.modelTokens, fed by merging the new
  ClaudeFileStat.hourlyByModel across files and filtering to the
  session window with the new sumBucketsByModel — same windowing rule
  sumBuckets already uses for the aggregate total. Lets a caller
  identify which model actually burned the most tokens this window
  and recompute cost under a different model's pricing.

  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
  ```

---

### Task 4: `ModelProjection` — dominant model + price ratios

**Files:**
- Create: `Sources/NotchAgent/Core/Services/ModelProjection.swift`
- Test: `Tests/NotchAgentTests/ModelProjectionTests.swift`

**Interfaces:**
- Consumes: `TokenUsage` (`Usage.swift`), `PricingTable.costUSD(model:usage:) -> Double?` (`PricingTable.swift`), `ClaudeQuotaProbe.modelRotation: [String]` (`ClaudeQuotaProbe.swift`).
- Produces:
  - `ModelProjection.Alternate: Sendable, Equatable, Identifiable` with `model: String`, `shortName: String`, `priceRatio: Double`.
  - `ModelProjection.dominantModel(modelTokens: [String: TokenUsage]) -> String?`
  - `ModelProjection.alternates(dominantModel: String, sessionTokens: TokenUsage, candidates: [String] = ClaudeQuotaProbe.modelRotation) -> [Alternate]`
  - `ModelProjection.shortName(for model: String) -> String`
  These are consumed by Task 6 (`BurnChartView`/`NotchExpandedView` wiring).

- [ ] **Step 1: Write the failing tests**

  Create `Tests/NotchAgentTests/ModelProjectionTests.swift`:

  ```swift
  import XCTest
  @testable import NotchAgent

  final class ModelProjectionTests: XCTestCase {
      func testDominantModelIsTheOneWithMostTokens() {
          let tokens: [String: TokenUsage] = [
              "claude-haiku-4-5-20251001": TokenUsage(input: 100, output: 0, cacheWrite: 0, cacheRead: 0),
              "claude-sonnet-5": TokenUsage(input: 10_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
          ]
          XCTAssertEqual(ModelProjection.dominantModel(modelTokens: tokens), "claude-sonnet-5")
      }

      func testDominantModelIsNilWhenNoUsage() {
          XCTAssertNil(ModelProjection.dominantModel(modelTokens: [:]))
      }

      func testAlternatesRatioReflectsRealPricing() {
          let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
          let alternates = ModelProjection.alternates(
              dominantModel: "claude-sonnet-5",
              sessionTokens: usage,
              candidates: ["claude-haiku-4-5-20251001", "claude-sonnet-5", "claude-opus-5", "claude-fable-5"]
          )
          let byShortName = Dictionary(uniqueKeysWithValues: alternates.map { ($0.shortName, $0.priceRatio) })
          // Sonnet itself is excluded — it's the dominant model, already the solid line.
          XCTAssertNil(byShortName["Sonnet"])
          // Sonnet: 3+15=18. Haiku: 1+5=6 -> 6/18. Opus: 5+25=30 -> 30/18. Fable: 10+50=60 -> 60/18.
          XCTAssertEqual(byShortName["Haiku"] ?? -1, 6.0 / 18.0, accuracy: 0.001)
          XCTAssertEqual(byShortName["Opus"] ?? -1, 30.0 / 18.0, accuracy: 0.001)
          XCTAssertEqual(byShortName["Fable"] ?? -1, 60.0 / 18.0, accuracy: 0.001)
      }

      func testAlternatesEmptyWhenDominantModelHasNoKnownPrice() {
          let usage = TokenUsage(input: 100, output: 100, cacheWrite: 0, cacheRead: 0)
          let alternates = ModelProjection.alternates(
              dominantModel: "totally-unknown-model",
              sessionTokens: usage,
              candidates: ["claude-sonnet-5"]
          )
          XCTAssertTrue(alternates.isEmpty)
      }

      func testAlternatesEmptyWhenSessionHasZeroTokens() {
          let alternates = ModelProjection.alternates(
              dominantModel: "claude-sonnet-5",
              sessionTokens: .zero,
              candidates: ["claude-haiku-4-5-20251001", "claude-opus-5"]
          )
          XCTAssertTrue(alternates.isEmpty)
      }

      func testShortNameMapsKnownFamilies() {
          XCTAssertEqual(ModelProjection.shortName(for: "claude-haiku-4-5-20251001"), "Haiku")
          XCTAssertEqual(ModelProjection.shortName(for: "claude-sonnet-5"), "Sonnet")
          XCTAssertEqual(ModelProjection.shortName(for: "claude-opus-5"), "Opus")
          XCTAssertEqual(ModelProjection.shortName(for: "claude-fable-5"), "Fable")
          XCTAssertEqual(ModelProjection.shortName(for: "gpt-5"), "gpt-5", "unknown family falls back to the raw id")
      }
  }
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/ModelProjectionTests`
  Expected: FAIL with a compile error — no such type `ModelProjection`.

- [ ] **Step 3: Write the implementation**

  Create `Sources/NotchAgent/Core/Services/ModelProjection.swift`:

  ```swift
  import Foundation

  /// Projects "what if I'd used a different model" for the burn chart — pure
  /// functions, fully unit-tested, mirroring BurnRate's shape (no I/O, no
  /// state). See docs/superpowers/specs/2026-08-15-burn-chart-multi-model-projection-design.md.
  public enum ModelProjection {
      /// One of the 4 Claude tiers, scaled relative to the dominant model.
      public struct Alternate: Sendable, Equatable, Identifiable {
          public var model: String
          public var shortName: String
          /// costUSD(model, sessionTokens) / costUSD(dominantModel, sessionTokens).
          /// >1 means this model would burn quota faster than what's shown;
          /// <1 means slower.
          public var priceRatio: Double

          public var id: String { model }

          public init(model: String, shortName: String, priceRatio: Double) {
              self.model = model
              self.shortName = shortName
              self.priceRatio = priceRatio
          }
      }

      /// The model with the most tokens spent in the current window — the
      /// model the chart's existing solid/dashed history line represents.
      public static func dominantModel(modelTokens: [String: TokenUsage]) -> String? {
          modelTokens.max { $0.value.total < $1.value.total }?.key
      }

      /// One alternate per candidate other than `dominantModel`. Silently
      /// skips a candidate PricingTable has no price for (never a
      /// fabricated $0 — see PricingTable.costUSD's contract) and returns
      /// nothing at all when the dominant model itself has no known price,
      /// or when there's nothing to scale (zero tokens this session).
      public static func alternates(
          dominantModel: String,
          sessionTokens: TokenUsage,
          candidates: [String] = ClaudeQuotaProbe.modelRotation
      ) -> [Alternate] {
          guard let dominantCost = PricingTable.costUSD(model: dominantModel, usage: sessionTokens),
                dominantCost > 0
          else { return [] }

          return candidates
              .filter { $0 != dominantModel }
              .compactMap { candidate in
                  guard let cost = PricingTable.costUSD(model: candidate, usage: sessionTokens) else { return nil }
                  return Alternate(model: candidate, shortName: shortName(for: candidate), priceRatio: cost / dominantCost)
              }
      }

      private static let families: [(key: String, name: String)] = [
          ("haiku", "Haiku"), ("sonnet", "Sonnet"), ("opus", "Opus"), ("fable", "Fable"),
      ]

      /// Short display name for a model id. Falls back to the raw id when
      /// it doesn't match one of the 4 known Claude families (e.g. a Codex
      /// model — out of scope for this feature, see the design spec).
      public static func shortName(for model: String) -> String {
          families.first { model.contains($0.key) }?.name ?? model
      }
  }
  ```

- [ ] **Step 4: Run test to verify it passes**

  Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test --filter NotchAgentTests/ModelProjectionTests`
  Expected: PASS — all `ModelProjectionTests` tests green.

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/NotchAgent/Core/Services/ModelProjection.swift Tests/NotchAgentTests/ModelProjectionTests.swift
  git commit -m "feat(model-projection): pure dominant-model + price-ratio calculator

  Mirrors BurnRate's shape: no I/O, fully unit-tested. dominantModel()
  picks the model with the most tokens in the window; alternates()
  gives each other Claude tier a price ratio against it, silently
  omitting any model PricingTable has no price for. Feeds the burn
  chart's multi-model projection lines (not yet wired into the view).

  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
  ```

---

### Task 5: `Theme` — 4 fixed per-model colors

**Files:**
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Components/Theme.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Theme.modelHaiku`, `Theme.modelSonnet`, `Theme.modelOpus`, `Theme.modelFable: Color` and `Theme.color(forModel model: String) -> Color`, consumed by Task 6 (`BurnChartView`).

No test cycle for this task — `Color` values aren't meaningfully assertable via XCTest (same as every other `Theme` constant in this file, none of which have tests today). Verification is `swift build` succeeding; the colors are eyeballed once Task 6 renders them.

- [ ] **Step 1: Add the 4 model colors and the lookup helper**

  In `Sources/NotchAgent/Features/NotchOverlay/Components/Theme.swift`, find the `// Chart & meter furniture` section:

  ```swift
      // Chart & meter furniture
      static let marker = dynamic(dark: .white, light: NSColor.black.withAlphaComponent(0.85))
      static let socket = dynamic(dark: NSColor.white.withAlphaComponent(0.10), light: NSColor.black.withAlphaComponent(0.10))
      static let gridline = dynamic(dark: NSColor.white.withAlphaComponent(0.06), light: NSColor.black.withAlphaComponent(0.08))
      static let gridStrong = dynamic(dark: NSColor.white.withAlphaComponent(0.18), light: NSColor.black.withAlphaComponent(0.22))
      static let bubble = dynamic(dark: NSColor.black.withAlphaComponent(0.85), light: NSColor.white.withAlphaComponent(0.95))
  ```

  Add right after `bubble`:

  ```swift
      // Burn-chart multi-model projection lines — 4 fixed hues, distinct
      // from coral (current model), ok/caution/warning/danger (state ramp).
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

      /// Fixed color identity for one of the 4 known Claude tiers — same
      /// substring match ModelProjection.shortName uses, so a model always
      /// reads as the same color whether or not it's the highlighted one.
      static func color(forModel model: String) -> Color {
          if model.contains("haiku") { return modelHaiku }
          if model.contains("sonnet") { return modelSonnet }
          if model.contains("opus") { return modelOpus }
          if model.contains("fable") { return modelFable }
          return textDim
      }
  ```

- [ ] **Step 2: Verify it builds**

  Run: `swift build`
  Expected: builds with no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add Sources/NotchAgent/Features/NotchOverlay/Components/Theme.swift
  git commit -m "feat(theme): fixed per-model colors for the burn chart's alternate lines

  4 hues distinct from the existing state ramp (ok/caution/warning/
  danger) and from coral (reserved for 'current model'), so each Claude
  tier keeps the same color whether or not it's the one highlighted.

  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
  ```

---

### Task 6: Wire the 3 alternate lines into `BurnChartView`

**Files:**
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift`
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Views/NotchExpandedView.swift`

**Interfaces:**
- Consumes: `ModelProjection.Alternate`, `ModelProjection.dominantModel(modelTokens:)`, `ModelProjection.alternates(dominantModel:sessionTokens:)` (Task 4), `Theme.color(forModel:)` (Task 5), `snapshot?.session?.modelTokens` / `snapshot?.session?.tokens` (Task 3).
- Produces: `BurnChartView` renders 3 additional dashed lines + a legend row. No new public interface for later tasks — this is the final task in the plan.

No dedicated unit test — this is `Canvas`-drawn UI, same as the file's existing `polyline`/`interpolate`/`drawScrubber`, none of which have XCTest coverage today. Verification is `swift build` plus a manual run (open the app, check the Burn page).

- [ ] **Step 1: Add the new params to `BurnChartView`**

  In `Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift`, the struct currently starts:

  ```swift
  struct BurnChartView: View {
      let samples: [PercentSample]
      let projection: BurnRate.Projection?
      let windowStart: Date
      let windowEnd: Date

      @State private var hoverX: CGFloat?
  ```

  Change to:

  ```swift
  struct BurnChartView: View {
      let samples: [PercentSample]
      let projection: BurnRate.Projection?
      let windowStart: Date
      let windowEnd: Date
      /// Display name of the model the solid/dashed history line already
      /// represents (e.g. "Sonnet") — nil hides the legend entirely.
      let dominantModelShortName: String?
      /// The 3 (or fewer) other Claude tiers, each with a price ratio
      /// against the dominant model. Empty hides the alternate lines.
      let alternates: [ModelProjection.Alternate]

      @State private var hoverX: CGFloat?
  ```

- [ ] **Step 2: Add the legend row to `body`**

  Still in `BurnChartView.swift`, `body` currently ends with:

  ```swift
              HStack {
                  GaugeLabel(text: "START \(Format.time(windowStart))", color: Theme.textFaint, size: 8)
                  Spacer()
                  GaugeLabel(text: "RESET \(Format.time(windowEnd))", color: Theme.coralDim, size: 8)
              }
          }
      }
  ```

  Change to add a legend row when there's something to show:

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

- [ ] **Step 3: Add `alternatePolyline` and draw the 3 lines**

  Still in `BurnChartView.swift`, add a new private method right after the existing `private var polyline: ...` computed property (before `private func interpolate`):

  ```swift
      /// Same shape as `polyline`, scaled by `alternate.priceRatio` — "if
      /// these tokens had all been on this model instead." Stops drawing
      /// once it would cross 100% (that model would already be exhausted;
      /// no marker, this is a context line, not the primary instrument).
      private func alternatePolyline(_ alternate: ModelProjection.Alternate) -> [(date: Date, percent: Double)] {
          let visible = visibleSamples
          guard let last = visible.last else { return [] }

          var points: [(Date, Double)] = []
          for sample in visible {
              let scaled = min(100, sample.percent * alternate.priceRatio)
              points.append((sample.date, scaled))
              if scaled >= 100 { return points }
          }

          guard let projection, projection.percentPerHour > 0.1 else { return points }
          let scaledRate = projection.percentPerHour * alternate.priceRatio
          guard scaledRate > 0.1 else { return points }

          let lastPercent = points.last?.1 ?? 0
          let hoursToFull = (100 - lastPercent) / scaledRate
          let exhaustsAt = last.date.addingTimeInterval(hoursToFull * 3600)
          if exhaustsAt <= windowEnd {
              points.append((exhaustsAt, 100))
          } else {
              let hours = windowEnd.timeIntervalSince(last.date) / 3600
              points.append((windowEnd, min(100, lastPercent + scaledRate * hours)))
          }
          return points
      }
  ```

  Then in `chart(in:)`, find the block that draws the primary projection line (`if let target = polyline.last, target.projected { ... }`) and, right after that whole `if` block closes (before the `// "Now": vertical hairline...` comment), add:

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

- [ ] **Step 4: Wire the call site in `NotchExpandedView`**

  In `Sources/NotchAgent/Features/NotchOverlay/Views/NotchExpandedView.swift`, inside `burnPage`, find:

  ```swift
      private var burnPage: some View {
          let focus = viewModel.focusProvider
          let snapshot = store.snapshots[focus]
          let session = snapshot?.session
          let end = session?.resetsAt ?? Date()
          let start = session?.startedAt ?? end.addingTimeInterval(-5 * 3600)
          let samples = store.percentHistory[focus] ?? []
          let projection = store.burnProjection(for: focus)
          let used = session?.usedPercent
          let verdict = burnVerdict(projection: projection, hasSamples: !samples.isEmpty)
  ```

  Add the projection computation right after `let verdict = ...`:

  ```swift
          let dominantModel = session?.modelTokens.flatMap { ModelProjection.dominantModel(modelTokens: $0) }
          let alternates = dominantModel.map { model in
              ModelProjection.alternates(dominantModel: model, sessionTokens: session?.tokens ?? .zero)
          } ?? []
          let dominantModelShortName = dominantModel.map(ModelProjection.shortName(for:))
  ```

  Then find the `BurnChartView(...)` call:

  ```swift
              BurnChartView(
                  samples: samples,
                  projection: projection,
                  windowStart: start,
                  windowEnd: end
              )
              .frame(maxHeight: .infinity)
  ```

  Change to:

  ```swift
              BurnChartView(
                  samples: samples,
                  projection: projection,
                  windowStart: start,
                  windowEnd: end,
                  dominantModelShortName: dominantModelShortName,
                  alternates: alternates
              )
              .frame(maxHeight: .infinity)
  ```

  This is the only call site (verified — `grep -rn "BurnChartView(" Sources` returns exactly this one match).

- [ ] **Step 5: Build and run**

  Run: `swift build`
  Expected: builds with no errors.

  Then launch the app (`Scripts/make-app.sh` or `swift run NotchAgent` per the project's existing dev workflow) and open the Burn page for the Claude provider. With recent Claude Code activity present, confirm: the highlighted model's solid/dashed line is unchanged from before this plan; up to 3 additional thin dashed lines appear in fixed colors; the legend row under the chart shows a colored dot + short name per model, including the highlighted one in coral.

- [ ] **Step 6: Run the full test suite**

  Run: `NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test`
  Expected: PASS — zero failures across the whole suite (required before push, per project convention).

- [ ] **Step 7: Commit**

  ```bash
  git add Sources/NotchAgent/Features/NotchOverlay/Components/BurnChartView.swift Sources/NotchAgent/Features/NotchOverlay/Views/NotchExpandedView.swift
  git commit -m "feat(burn-chart): show 3 alternate-model projection lines

  Reuses the existing % USED axis — no new metric. Each alternate line
  is the real solid+dashed history scaled by that model's price ratio
  against the model that actually burned the most tokens this window
  (ModelProjection.alternates), so it reads as 'if these tokens had
  all been on this model instead.' Fixed color per model (Theme.color
  forModel:), legend row under the chart. Highlighted model's own line
  is visually unchanged.

  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
  ```

---

## Self-Review Notes

- **Spec coverage:** Pré-requisito de pricing → Task 1. Fonte de dados por modelo na janela de 5h → Tasks 2–3. Modelo em destaque + fatores de preço → Task 4. Cores fixas + legenda → Task 5. Renderização das 3 linhas + edge cases (cap em 100%, omissão silenciosa, sessão vazia) → Task 6 (cap/omission logic lives in `alternatePolyline`/`ModelProjection`, already tested in Task 4 for the omission/empty cases; the 100%-cap behavior in `alternatePolyline` itself is UI-layer, covered by the same no-unit-test convention as its siblings, called out explicitly in Task 6's header). Codex replica and per-line toggle are explicitly out of scope in the spec and not tasked here.
- **Placeholder scan:** no TBD/TODO, every step has literal code, every test has real assertions with computed expected values (not "assert something").
- **Type consistency checked:** `ModelProjection.Alternate` (Task 4) → same shape used in `BurnChartView`'s `alternates: [ModelProjection.Alternate]` param and `alternatePolyline(_ alternate: ModelProjection.Alternate)` (Task 6). `SessionUsage.modelTokens: [String: TokenUsage]?` (Task 3) → same optional-dictionary type consumed via `session?.modelTokens.flatMap { ... }` in Task 6. `ModelProjection.dominantModel(modelTokens:) -> String?` and `ModelProjection.shortName(for:) -> String` signatures match their Task 6 call sites exactly.
