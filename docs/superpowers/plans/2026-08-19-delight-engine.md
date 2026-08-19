# Delight Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Camada "delight sem anúncio": mascote com vida própria (agência simulada, memória persistente), catálogo de momentos, som/háptica sintetizados e tinta de fundo por hora do dia, tudo sob um toggle mestre.

**Architecture:** `MascotMind` (observable, MainActor, tick 60s) embrulha um núcleo puro (`MascotMindCore` + `DelightCatalog` + `DelightSignals`) que é 100% determinístico com RNG injetável — toda a lógica de humor, teimosia, cooldown e detecção de eventos é testada sem timers. Animação procedural (`MascotPuppetView`) transforma os sprites existentes; som é sintetizado via `AVAudioEngine`; tinta por hora do dia é um gradiente sobre o painel quando o clima está desligado.

**Tech Stack:** Swift 6 / SwiftUI / AppKit (macOS 14+), XCTest, AVAudioEngine, JSONEncoder/Decoder.

## Global Constraints

- Projeto SwiftPM: build `swift build`, testes `swift test` (suíte atual: 433 testes, 0 falhas).
- Target: `NotchAgent` (módulo importado nos testes como `@testable import NotchAgent`); testes em `Tests/NotchAgentTests/`.
- Regra de ouro do design: **nunca interromper, nunca piscar** — nenhuma reação pode roubar foco ou animar por mais de ~1,5s.
- Cooldown de reação: 90s entre gestos; o mesmo gesto nunca repete consecutivamente.
- Teimosia: 2 ignoradas seguidas → a 3ª reação é forçada.
- Acessibilidade: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` congela animação; `NSWorkspace.shared.isVoiceOverEnabled` silencia som.
- Toggle mestre: `preferences.settings.delightEnabled` (default `true`); desligado = sem gesto, som, háptica ou tinta.
- Commits com pathspec explícito; arquivos de release (CHANGELOG.md, README.md, Resources/Info.plist, VERSION, docs/styles.css) ficam permanentemente staged — nunca incluir no pathspec.
- Deploy local: `pkill -9 -x NotchAgent; sleep 1; ./Scripts/make-app.sh && rm -rf /Applications/NotchAgent.app && cp -R dist/NotchAgent.app /Applications/ && open /Applications/NotchAgent.app`.

## File Structure

**Create:**
- `Sources/NotchAgent/Features/Delight/MascotMindCore.swift` — estado, humor, nudge, escolha de gesto, RNG determinístico (`SplitMix64`).
- `Sources/NotchAgent/Features/Delight/DelightCatalog.swift` — momento → peso + gestos elegíveis + bumps de afeto.
- `Sources/NotchAgent/Features/Delight/DelightSignals.swift` — detectores puros: reset de quota, meia-noite, dia, tinta por hora.
- `Sources/NotchAgent/Features/Delight/MascotMindPersistence.swift` — JSON em Application Support.
- `Sources/NotchAgent/Features/Delight/MascotMind.swift` — wrapper observable + tick + wiring.
- `Sources/NotchAgent/Features/Delight/MascotPuppetView.swift` — transformações procedurais + tabela `PuppetMotion`.
- `Sources/NotchAgent/Features/Delight/DelightSounds.swift` — síntese AVAudioEngine + eligibility.
- `Sources/NotchAgent/Features/Delight/TimeTintView.swift` — gradiente por hora do dia.

**Modify:**
- `Sources/NotchAgent/Core/Models/AppSettings.swift` — campo `delightEnabled`.
- `Sources/NotchAgent/Features/Settings/SettingsView.swift` — toggle mestre.
- `Sources/NotchAgent/App/AppEnvironment.swift` — criar `mind`, passar ao controller, hook `onRestore`, `start()`.
- `Sources/NotchAgent/Features/NotchOverlay/Windowing/NotchWindowController.swift` — parâmetro `mind` + `.environment(mind)`.
- `Sources/NotchAgent/Features/NotchOverlay/Views/NotchContainerView.swift` — tinta + `noteExpanded`.
- `Sources/NotchAgent/Features/NotchOverlay/Components/ProviderCardView.swift` — envolver o mascote no puppet.

**Tests:**
- `Tests/NotchAgentTests/AppSettingsDelightTests.swift`
- `Tests/NotchAgentTests/MascotMindCoreTests.swift`
- `Tests/NotchAgentTests/DelightSignalsTests.swift`
- `Tests/NotchAgentTests/MascotMindPersistenceTests.swift`
- `Tests/NotchAgentTests/PuppetMotionTests.swift`
- `Tests/NotchAgentTests/DelightSoundsTests.swift`

---

### Task 1: Toggle mestre — campo `delightEnabled` + UI

**Files:**
- Modify: `Sources/NotchAgent/Core/Models/AppSettings.swift` (campo + CodingKeys + decode)
- Modify: `Sources/NotchAgent/Features/Settings/SettingsView.swift` (toggle na seção Notch)
- Test: `Tests/NotchAgentTests/AppSettingsDelightTests.swift`

**Interfaces:**
- Consumes: padrão existente de decode manual do `AppSettings` (ver `weatherEnabled`, linhas 67/108/164).
- Produces: `AppSettings.delightEnabled: Bool` (default `true`) — consumido pelas Tasks 4–8.

- [ ] **Step 1: Write the failing test**

Create `Tests/NotchAgentTests/AppSettingsDelightTests.swift`:

```swift
import XCTest
@testable import NotchAgent

final class AppSettingsDelightTests: XCTestCase {
    private func decode(_ json: String) -> AppSettings? {
        try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testDelightEnabledDefaultsToTrueOnLegacyPayload() {
        let settings = decode("{\"themeMode\":\"auto\"}")
        XCTAssertEqual(settings?.delightEnabled, true, "legacy payload without the key must enable delight")
    }

    func testDelightEnabledDecodesWhenPresent() {
        let settings = decode("{\"delightEnabled\":false}")
        XCTAssertEqual(settings?.delightEnabled, false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppSettingsDelightTests`
Expected: FAIL — `value of type 'AppSettings' has no member 'delightEnabled'`

- [ ] **Step 3: Write minimal implementation**

In `AppSettings.swift`, after `public var weatherEnabled: Bool = true` (line 67):

```swift
    /// Delight layer (mascot reactions, moments, sound/haptics, time tint):
    /// one master switch — off means a sober panel.
    public var delightEnabled: Bool = true
```

Add `case delightEnabled` to `CodingKeys` (after `case weatherEnabled`), and in `init(from:)` after the `weatherEnabled` line:

```swift
        delightEnabled = try container.decodeIfPresent(Bool.self, forKey: .delightEnabled) ?? true
```

In `SettingsView.swift`, find the Notch section (the weather toggle around line 132) and add right after the weather `Toggle` block, in the same `Section`:

```swift
            Toggle(
                pt
                    ? "Efeitos e reações do painel (mascote, som e tinta do fundo)"
                    : "Panel effects and reactions (mascot, sound and background tint)",
                isOn: $preferences.settings.delightEnabled
            )
```

(Match the exact `pt ? ... : ...` pattern and `$preferences.settings` binding used by the weather toggle next to it.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppSettingsDelightTests`
Expected: PASS (2 tests). Then full: `swift test` — 435 testes, 0 falhas.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Core/Models/AppSettings.swift Sources/NotchAgent/Features/Settings/SettingsView.swift Tests/NotchAgentTests/AppSettingsDelightTests.swift
git commit -m "feat(delight): toggle mestre delightEnabled no AppSettings e nas configurações"
```

---

### Task 2: Núcleo puro — MascotMindCore + DelightCatalog

**Files:**
- Create: `Sources/NotchAgent/Features/Delight/MascotMindCore.swift`
- Create: `Sources/NotchAgent/Features/Delight/DelightCatalog.swift`
- Test: `Tests/NotchAgentTests/MascotMindCoreTests.swift`

**Interfaces:**
- Consumes: nada (módulo raiz da feature).
- Produces (usado pelas Tasks 3–8):
  - `enum MascotGesture: String, Codable, CaseIterable, Sendable` — cases `none, ignored, blink, lookAtCursor, tilt, hop, stretch, yawn, nod`
  - `enum MascotMood: String, Codable, CaseIterable, Sendable` — cases `curious, calm, sleepy, alert`
  - `enum DelightMoment: String, Codable, CaseIterable, Sendable` — cases `quotaReset, peakPassed, midnight, firstExpandOfDay, idleThirtySeconds, randomExpand`
  - `struct MascotMindState: Codable, Equatable, Sendable` — campos `mood, energy, affection, lastSeen: Date?, lastExpandedDay: String?, lastGesture: MascotGesture?, ignoresInARow: Int, gestureCooldownUntil: Date?` + `init` com defaults.
  - `struct SplitMix64: RandomNumberGenerator` — `init(seed: UInt64)`
  - `enum MascotMindCore` — `recomputeMood(energy:affection:burnHigh:) -> MascotMood`, `evolveTick(state:now:idleSeconds:burnHigh:)`, `nudge(state:moment:now:rng:) -> MascotGesture`, `chooseGesture(state:moment:rng:) -> MascotGesture`, `selfInitiatedGesture(state:now:rng:) -> MascotGesture`, `firstExpandOfDay(state:dayKey:) -> Bool`
  - `enum DelightCatalog` — `reactionCooldown: TimeInterval = 90`, `weight(for:) -> Double`, `gestures(for:) -> [MascotGesture]`, `affectionBump(firstExpandOfDay:) -> Double`, `affectionAbsencePenalty(absentDays:) -> Double`

- [ ] **Step 1: Write the failing test**

Create `Tests/NotchAgentTests/MascotMindCoreTests.swift`:

```swift
import XCTest
@testable import NotchAgent

final class MascotMindCoreTests: XCTestCase {
    private var rng = SplitMix64(seed: 42)
    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    func testRecomputeMoodStates() {
        XCTAssertEqual(MascotMindCore.recomputeMood(energy: 0.9, affection: 0.9, burnHigh: true), .alert)
        XCTAssertEqual(MascotMindCore.recomputeMood(energy: 0.1, affection: 0.5, burnHigh: false), .sleepy)
        XCTAssertEqual(MascotMindCore.recomputeMood(energy: 0.9, affection: 0.9, burnHigh: false), .curious)
        XCTAssertEqual(MascotMindCore.recomputeMood(energy: 0.5, affection: 0.2, burnHigh: false), .calm)
    }

    func testEvolveTickDecaysEnergyAndClamps() {
        var state = MascotMindState(energy: 1)
        MascotMindCore.evolveTick(state: &state, now: now, idleSeconds: 0, burnHigh: false)
        XCTAssertEqual(state.energy, 1, accuracy: 0.0001, "zero idle time must not decay energy")

        MascotMindCore.evolveTick(state: &state, now: now.addingTimeInterval(60), idleSeconds: 60, burnHigh: false)
        XCTAssertEqual(state.energy, 1 - 60 * 0.00005, accuracy: 0.0001)
        XCTAssertEqual(state.lastSeen, now.addingTimeInterval(60))
    }

    func testNudgeRespectsCooldown() {
        var state = MascotMindState()
        state.gestureCooldownUntil = now.addingTimeInterval(30)
        let gesture = MascotMindCore.nudge(state: &state, moment: .quotaReset, now: now, rng: &rng)
        XCTAssertEqual(gesture, .none, "within cooldown, no reaction may fire")
        XCTAssertEqual(state.lastGesture, nil)
    }

    func testNudgeCanBeIgnoredButSometimesReacts() {
        var state = MascotMindState(affection: 0)  // ignoreChance máximo: 0.35
        var reacts = 0
        var ignores = 0
        for _ in 0..<200 {
            var s = MascotMindState(affection: 0)
            let g = MascotMindCore.nudge(state: &s, moment: .quotaReset, now: now, rng: &rng)
            if g == .ignored { ignores += 1 } else if g != .none { reacts += 1 }
        }
        XCTAssertGreaterThan(ignores, 0, "with affection 0 the mascot must sometimes ignore")
        XCTAssertGreaterThan(reacts, 0, "and sometimes react")
    }

    func testTeimosiaForcesReactionAfterTwoIgnores() {
        var state = MascotMindState(affection: 0, ignoresInARow: 2)
        let gesture = MascotMindCore.nudge(state: &state, moment: .quotaReset, now: now, rng: &rng)
        XCTAssertNotEqual(gesture, .ignored, "two consecutive ignores force the third reaction")
        XCTAssertEqual(state.ignoresInARow, 0)
        XCTAssertNotNil(state.gestureCooldownUntil)
    }

    func testReactionSetsCooldownOf90Seconds() {
        // Teimosia garante a reação — o teste não pode depender de sorte.
        var state = MascotMindState(affection: 1, ignoresInARow: 2)
        let gesture = MascotMindCore.nudge(state: &state, moment: .quotaReset, now: now, rng: &rng)
        XCTAssertNotEqual(gesture, .ignored)
        XCTAssertEqual(state.gestureCooldownUntil, now.addingTimeInterval(DelightCatalog.reactionCooldown))
    }

    func testChooseGestureNeverPicksLastGesture() {
        let state = MascotMindState(mood: .curious, lastGesture: .blink)
        for _ in 0..<50 {
            let g = MascotMindCore.chooseGesture(state: state, moment: .randomExpand, rng: &rng)
            XCTAssertNotEqual(g, .blink, "the same gesture never repeats consecutively")
        }
    }

    func testChooseGestureOnlyPicksCatalogGestures() {
        var state = MascotMindState(mood: .calm)
        for _ in 0..<50 {
            let g = MascotMindCore.chooseGesture(state: state, moment: .quotaReset, rng: &rng)
            XCTAssertTrue(DelightCatalog.gestures(for: .quotaReset).contains(g))
        }
    }

    func testSelfInitiatedGestureRespectsCooldownAndSetsIt() {
        var state = MascotMindState(energy: 1)
        for _ in 0..<50 {
            let g = MascotMindCore.selfInitiatedGesture(state: &state, now: now, rng: &rng)
            if g != .none {
                XCTAssertNotNil(state.gestureCooldownUntil)
                return
            }
        }
        XCTFail("with full energy, 50 attempts must self-initiate at least once")
    }

    func testFirstExpandOfDay() {
        let state = MascotMindState(lastExpandedDay: "2026-08-18")
        XCTAssertTrue(MascotMindCore.firstExpandOfDay(state: state, dayKey: "2026-08-19"))
        XCTAssertFalse(MascotMindCore.firstExpandOfDay(state: state, dayKey: "2026-08-18"))
        XCTAssertTrue(MascotMindCore.firstExpandOfDay(state: MascotMindState(), dayKey: "2026-08-19"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MascotMindCoreTests`
Expected: FAIL — cannot find type `MascotMindCore` in scope.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/NotchAgent/Features/Delight/MascotMindCore.swift`:

```swift
import Foundation

/// One micro-reaction of the mascot. `.ignored` means the mascot DECIDED
/// not to react (agency); `.none` means no signal was offered.
public enum MascotGesture: String, Codable, CaseIterable, Sendable {
    case none, ignored, blink, lookAtCursor, tilt, hop, stretch, yawn, nod
}

public enum MascotMood: String, Codable, CaseIterable, Sendable {
    case curious, calm, sleepy, alert
}

public enum DelightMoment: String, Codable, CaseIterable, Sendable {
    case quotaReset, peakPassed, midnight, firstExpandOfDay, idleThirtySeconds, randomExpand
}

/// The mascot's persistent inner life. Everything the engine needs to feel
/// continuous across launches.
public struct MascotMindState: Codable, Equatable, Sendable {
    public var mood: MascotMood
    public var energy: Double
    public var affection: Double
    public var lastSeen: Date?
    public var lastExpandedDay: String?
    public var lastGesture: MascotGesture?
    public var ignoresInARow: Int
    public var gestureCooldownUntil: Date?

    public init(
        mood: MascotMood = .calm,
        energy: Double = 0.8,
        affection: Double = 0.5,
        lastSeen: Date? = nil,
        lastExpandedDay: String? = nil,
        lastGesture: MascotGesture? = nil,
        ignoresInARow: Int = 0,
        gestureCooldownUntil: Date? = nil
    ) {
        self.mood = mood
        self.energy = energy
        self.affection = affection
        self.lastSeen = lastSeen
        self.lastExpandedDay = lastExpandedDay
        self.lastGesture = lastGesture
        self.ignoresInARow = ignoresInARow
        self.gestureCooldownUntil = gestureCooldownUntil
    }
}

/// Deterministic RNG for tests; production uses SystemRandomNumberGenerator.
public struct SplitMix64: RandomNumberGenerator {
    public var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Pure engine: no timers, no actors. Deterministic for a given RNG.
public enum MascotMindCore {
    /// Energy decays slowly with idle time: ~0.18/h.
    static let energyDecayPerSecond = 0.00005

    public static func recomputeMood(energy: Double, affection: Double, burnHigh: Bool) -> MascotMood {
        if burnHigh { return .alert }
        if energy < 0.3 { return .sleepy }
        if energy > 0.7 && affection > 0.6 { return .curious }
        return .calm
    }

    public static func evolveTick(state: inout MascotMindState, now: Date, idleSeconds: Double, burnHigh: Bool) {
        state.energy = min(1, max(0, state.energy - idleSeconds * energyDecayPerSecond))
        state.mood = recomputeMood(energy: state.energy, affection: state.affection, burnHigh: burnHigh)
        state.lastSeen = now
    }

    /// Events push; the mascot decides. Never reacts within the cooldown.
    /// Chance to ignore shrinks with affection and with event importance;
    /// two consecutive ignores force the third (teimosia).
    public static func nudge(
        state: inout MascotMindState,
        moment: DelightMoment,
        now: Date,
        rng: inout some RandomNumberGenerator
    ) -> MascotGesture {
        if let until = state.gestureCooldownUntil, until > now {
            return .none
        }
        let weight = DelightCatalog.weight(for: moment)
        let ignoreChance = max(0.05, 0.35 - 0.25 * state.affection) * (1.0 - weight * 0.5)
        if state.ignoresInARow < 2, Double.random(in: 0..<1, using: &rng) < ignoreChance {
            state.ignoresInARow += 1
            return .ignored
        }
        let gesture = chooseGesture(state: state, moment: moment, rng: &rng)
        state.ignoresInARow = 0
        state.lastGesture = gesture
        state.gestureCooldownUntil = now.addingTimeInterval(DelightCatalog.reactionCooldown)
        return gesture
    }

    /// Weighted roulette over the catalog gestures for the moment, filtered
    /// by mood affinity and never the same gesture twice in a row. The
    /// catalog is the invariant: if the mood has no affinity for any
    /// eligible gesture, the whole catalog is weighted equally instead —
    /// the reaction ALWAYS belongs to its moment.
    public static func chooseGesture(
        state: MascotMindState,
        moment: DelightMoment,
        rng: inout some RandomNumberGenerator
    ) -> MascotGesture {
        let affinity = gestureAffinity(state.mood)
        let catalog = DelightCatalog.gestures(for: moment)
        let eligible = catalog.filter { $0 != state.lastGesture }
        guard !eligible.isEmpty else { return catalog.first ?? .blink }
        let moodAligned = eligible.filter { affinity[$0] != nil }
        let pool = moodAligned.isEmpty ? eligible : moodAligned
        let total = pool.reduce(0.0) { $0 + (affinity[$1] ?? 0.5) }
        var roll = Double.random(in: 0..<total, using: &rng)
        for gesture in pool {
            roll -= affinity[gesture] ?? 0.5
            if roll <= 0 { return gesture }
        }
        return pool.last ?? catalog.first ?? .blink
    }

    /// Unprompted gesture: the mascot acts on its own, more when energetic.
    public static func selfInitiatedGesture(
        state: inout MascotMindState,
        now: Date,
        rng: inout some RandomNumberGenerator
    ) -> MascotGesture {
        if let until = state.gestureCooldownUntil, until > now {
            return .none
        }
        guard Double.random(in: 0..<1, using: &rng) < 0.15 * state.energy else {
            return .none
        }
        let gesture = chooseGesture(state: state, moment: .randomExpand, rng: &rng)
        state.lastGesture = gesture
        state.gestureCooldownUntil = now.addingTimeInterval(DelightCatalog.reactionCooldown)
        return gesture
    }

    public static func firstExpandOfDay(state: MascotMindState, dayKey: String) -> Bool {
        state.lastExpandedDay != dayKey
    }

    private static func gestureAffinity(_ mood: MascotMood) -> [MascotGesture: Double] {
        switch mood {
        case .alert: [.blink: 0.5, .nod: 0.5]
        case .sleepy: [.yawn: 0.6, .blink: 0.4]
        case .curious: [.lookAtCursor: 0.3, .tilt: 0.3, .hop: 0.2, .stretch: 0.2]
        case .calm: [.blink: 0.4, .tilt: 0.3, .stretch: 0.3]
        }
    }
}
```

Create `Sources/NotchAgent/Features/Delight/DelightCatalog.swift`:

```swift
import Foundation

/// The fan of moments and their weights — "sem anúncio": low weights mean
/// the mascot often just carries on.
public enum DelightCatalog {
    /// One reaction per 90s at most.
    public static let reactionCooldown: TimeInterval = 90

    public static func weight(for moment: DelightMoment) -> Double {
        switch moment {
        case .quotaReset: 0.9
        case .firstExpandOfDay: 0.8
        case .peakPassed: 0.7
        case .midnight: 0.6
        case .idleThirtySeconds: 0.4
        case .randomExpand: 0.3
        }
    }

    public static func gestures(for moment: DelightMoment) -> [MascotGesture] {
        switch moment {
        case .quotaReset: [.nod, .hop]
        case .firstExpandOfDay: [.lookAtCursor, .tilt]
        case .peakPassed: [.stretch, .blink]
        case .midnight: [.yawn, .blink]
        case .idleThirtySeconds: [.lookAtCursor, .blink]
        case .randomExpand: [.blink, .hop, .tilt, .stretch]
        }
    }

    public static func affectionBump(firstExpandOfDay: Bool) -> Double {
        firstExpandOfDay ? 0.02 : 0
    }

    /// Being ignored for days cools the mascot off — capped so it never
    /// becomes unreachable.
    public static func affectionAbsencePenalty(absentDays: Int) -> Double {
        Double(min(max(absentDays, 0), 5)) * 0.01
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MascotMindCoreTests`
Expected: PASS (11 tests). Then `swift build` — deve compilar (DelightCatalog/MascotMindCore ainda sem consumidores).

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Features/Delight/MascotMindCore.swift Sources/NotchAgent/Features/Delight/DelightCatalog.swift Tests/NotchAgentTests/MascotMindCoreTests.swift
git commit -m "feat(delight): núcleo puro do motor — humor, teimosia, cooldown, catálogo de momentos"
```

---

### Task 3: Detectores — DelightSignals

**Files:**
- Create: `Sources/NotchAgent/Features/Delight/DelightSignals.swift`
- Test: `Tests/NotchAgentTests/DelightSignalsTests.swift`

**Interfaces:**
- Consumes: `GaugeMetric.from(_ snapshot: UsageSnapshot?) -> GaugeMetric?` (existente em `Sources/NotchAgent/Core/Models/Usage.swift:236`, com `.remaining: Double`).
- Produces (usado pelas Tasks 4, 7, 8):
  - `enum DelightSignals` — `dayKey(_:calendar:) -> String`, `crossedMidnight(previous:now:calendar:) -> Bool`, `quotaResetDetected(previous:current:) -> Bool`, `enum TimeTintKey: String, CaseIterable` cases `night, dawn, day, dusk`, `timeTint(at:calendar:) -> TimeTintKey`, `tintColor(for:) -> NSColor`

- [ ] **Step 1: Write the failing test**

Create `Tests/NotchAgentTests/DelightSignalsTests.swift`:

```swift
import XCTest
import AppKit
@testable import NotchAgent

final class DelightSignalsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testDayKeyIsStable() {
        // 1_756_000_000 epoch = 2025-08-24T01:46:40Z.
        let date = Date(timeIntervalSince1970: 1_756_000_000)
        XCTAssertEqual(DelightSignals.dayKey(date, calendar: calendar), "2025-08-24")
    }

    func testCrossedMidnight() {
        let previous = Date(timeIntervalSince1970: 1_756_000_000)
        let sameDay = previous.addingTimeInterval(60)
        let nextDay = previous.addingTimeInterval(86_400)
        XCTAssertFalse(DelightSignals.crossedMidnight(previous: previous, now: sameDay, calendar: calendar))
        XCTAssertTrue(DelightSignals.crossedMidnight(previous: previous, now: nextDay, calendar: calendar))
    }

    func testQuotaResetDetectedOnBigJump() {
        XCTAssertTrue(DelightSignals.quotaResetDetected(
            previous: GaugeMetric.from(DelightFixtures.snapshot(remaining: 5)),
            current: GaugeMetric.from(DelightFixtures.snapshot(remaining: 80))
        ))
        XCTAssertFalse(DelightSignals.quotaResetDetected(
            previous: GaugeMetric.from(DelightFixtures.snapshot(remaining: 40)),
            current: GaugeMetric.from(DelightFixtures.snapshot(remaining: 60))
        ))
        XCTAssertFalse(DelightSignals.quotaResetDetected(previous: nil, current: nil))
    }

    func testTimeTintKeyframes() {
        func key(hour: Int) -> DelightSignals.TimeTintKey {
            let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: hour))!
            return DelightSignals.timeTint(at: date, calendar: calendar)
        }
        XCTAssertEqual(key(hour: 2), .night)
        XCTAssertEqual(key(hour: 4), .night)
        XCTAssertEqual(key(hour: 5), .dawn)
        XCTAssertEqual(key(hour: 8), .dawn)
        XCTAssertEqual(key(hour: 9), .day)
        XCTAssertEqual(key(hour: 16), .day)
        XCTAssertEqual(key(hour: 17), .dusk)
        XCTAssertEqual(key(hour: 19), .dusk)
        XCTAssertEqual(key(hour: 20), .night)
    }

    func testTintColorsDifferPerKey() {
        let colors = Set(DelightSignals.TimeTintKey.allCases.map { DelightSignals.tintColor(for: $0) })
        XCTAssertEqual(colors.count, DelightSignals.TimeTintKey.allCases.count)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DelightSignalsTests`
Expected: FAIL — cannot find `DelightSignals` (e `Fixtures.snapshot` ainda não existe).

- [ ] **Step 3: Write minimal implementation**

Create `Sources/NotchAgent/Features/Delight/DelightSignals.swift`:

```swift
import AppKit
import Foundation

/// Pure event detection — nothing here touches timers or the UI.
public enum DelightSignals {
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func crossedMidnight(previous: Date, now: Date, calendar: Calendar = .current) -> Bool {
        dayKey(previous, calendar: calendar) != dayKey(now, calendar: calendar)
    }

    /// A quota reset looks like the remaining percent jumping up ≥ 30 points
    /// between two refreshes of the same provider.
    public static func quotaResetDetected(previous: GaugeMetric?, current: GaugeMetric?) -> Bool {
        guard let previous, let current else { return false }
        return current.remaining - previous.remaining >= 30
    }

    public enum TimeTintKey: String, CaseIterable, Sendable {
        case night, dawn, day, dusk
    }

    public static func timeTint(at date: Date, calendar: Calendar = .current) -> TimeTintKey {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 20..<24, 0..<5: .night
        case 5..<9: .dawn
        case 9..<17: .day
        default: .dusk
        }
    }

    /// Low-opacity washes over the black panel — only when weather is OFF.
    public static func tintColor(for key: TimeTintKey) -> NSColor {
        switch key {
        case .night: NSColor(red: 0.03, green: 0.04, blue: 0.09, alpha: 0.10)
        case .dawn: NSColor(red: 0.55, green: 0.45, blue: 0.62, alpha: 0.08)
        case .day: NSColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 0.04)
        case .dusk: NSColor(red: 0.75, green: 0.45, blue: 0.20, alpha: 0.09)
        }
    }
}
```

The test references `Fixtures.snapshot(remaining:)` — the `Tests/NotchAgentTests/Fixtures` folder already holds fixture helpers; add to an existing fixtures file (create `Tests/NotchAgentTests/Fixtures/DelightFixtures.swift`):

```swift
import Foundation
@testable import NotchAgent

enum DelightFixtures {
    /// Minimal UsageSnapshot whose GaugeMetric reads `remaining`.
    static func snapshot(remaining: Double) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claudeCode,
            session: UsageScope(
                usedPercent: 100 - remaining,
                resetsAt: Date(),
                tokens: .zero,
                namedQuotas: [],
                usedPercentIsFromQuota: true
            ),
            weekly: nil,
            modelBreakdown: [],
            health: .ok,
            note: nil,
            activeModel: nil,
            quotaStatus: .ok,
            accountUsage: [],
            fetchedAt: Date()
        )
    }
}
```

> Note: `UsageSnapshot`'s real memberwise init may differ — at implementation time, read `Sources/NotchAgent/Core/Models/Usage.swift` and adapt `DelightFixtures.snapshot` to the real initializer. The test already calls `DelightFixtures.snapshot(remaining:)`; the behavior under test does not change.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DelightSignalsTests`
Expected: PASS (5 tests). Full suite: `swift test` — 440 testes, 0 falhas.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Features/Delight/DelightSignals.swift Tests/NotchAgentTests/DelightSignalsTests.swift Tests/NotchAgentTests/Fixtures/DelightFixtures.swift
git commit -m "feat(delight): detectores puros — reset de quota, meia-noite, tinta por hora do dia"
```

---

### Task 4: Persistência — MascotMindPersistence

**Files:**
- Create: `Sources/NotchAgent/Features/Delight/MascotMindPersistence.swift`
- Test: `Tests/NotchAgentTests/MascotMindPersistenceTests.swift`

**Interfaces:**
- Consumes: `MascotMindState` (Task 2).
- Produces (usado pela Task 5):
  - `struct MascotMindPersistence` — `init(directory: URL?)`, `func load() -> MascotMindState`, `func save(_ state: MascotMindState)`

- [ ] **Step 1: Write the failing test**

Create `Tests/NotchAgentTests/MascotMindPersistenceTests.swift`:

```swift
import XCTest
import Foundation
@testable import NotchAgent

final class MascotMindPersistenceTests: XCTestCase {
    private var tempDir: URL!
    private var persistence: MascotMindPersistence!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mascot-mind-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        persistence = MascotMindPersistence(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRoundTrip() {
        var state = MascotMindState()
        state.mood = .sleepy
        state.energy = 0.42
        state.affection = 0.77
        state.lastExpandedDay = "2026-08-19"
        state.lastGesture = .yawn
        state.ignoresInARow = 1
        state.gestureCooldownUntil = Date(timeIntervalSince1970: 1_756_100_000)

        persistence.save(state)
        let loaded = persistence.load()

        XCTAssertEqual(loaded, state)
    }

    func testMissingFileLoadsFreshState() {
        let loaded = persistence.load()
        XCTAssertEqual(loaded, MascotMindState())
    }

    func testCorruptFileLoadsFreshState() {
        try? "not json at all".write(to: tempDir.appendingPathComponent("mascot-mind.json"), atomically: true, encoding: .utf8)
        let loaded = persistence.load()
        XCTAssertEqual(loaded, MascotMindState())
    }

    func testLegacyPayloadWithoutNewFieldsLoadsWithDefaults() {
        let legacy = """
        {"mood":"curious","energy":0.9}
        """
        try? legacy.write(to: tempDir.appendingPathComponent("mascot-mind.json"), atomically: true, encoding: .utf8)
        let loaded = persistence.load()
        XCTAssertEqual(loaded.mood, .curious)
        XCTAssertEqual(loaded.energy, 0.9)
        XCTAssertEqual(loaded.affection, 0.5, "missing fields must fall back to defaults")
        XCTAssertNil(loaded.lastGesture)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MascotMindPersistenceTests`
Expected: FAIL — cannot find `MascotMindPersistence`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/NotchAgent/Features/Delight/MascotMindPersistence.swift`:

```swift
import Foundation

/// JSON persistence for the mascot's inner life. A corrupt or missing file
/// is a fresh start — the mascot is never blocked by a bad save.
public struct MascotMindPersistence {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("NotchAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("mascot-mind.json")
    }

    public func load() -> MascotMindState {
        guard let data = try? Data(contentsOf: fileURL) else { return MascotMindState() }
        let decoder = JSONDecoder()
        // Dates come from state snapshots; tolerate both ms and s precision.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(Double.self)
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        guard let state = try? decoder.decode(MascotMindState.self, from: data) else {
            return MascotMindState()
        }
        return state
    }

    public func save(_ state: MascotMindState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MascotMindPersistenceTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Features/Delight/MascotMindPersistence.swift Tests/NotchAgentTests/MascotMindPersistenceTests.swift
git commit -m "feat(delight): persistência JSON do estado do mascote em Application Support"
```

---

### Task 5: Wrapper + wiring — MascotMind, AppEnvironment, NotchWindowController

**Files:**
- Create: `Sources/NotchAgent/Features/Delight/MascotMind.swift`
- Modify: `Sources/NotchAgent/App/AppEnvironment.swift` (campo `mind`, criação no init, hook `onRestore`, `mind.start()` no bootstrap)
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Windowing/NotchWindowController.swift` (parâmetro `mind` + `.environment(mind)`)

**Interfaces:**
- Consumes: `MascotMindCore`, `DelightCatalog`, `DelightSignals`, `MascotMindPersistence`, `GaugeMetric`, `PreferencesStore` (campo `.settings.delightEnabled` da Task 1), `UsageStore.snapshots: [ProviderID: UsageSnapshot]`, `UsageStore.onRestore: ((RestoreMoment) -> Void)?`.
- Produces (usado pelas Tasks 6–8):
  - `@MainActor @Observable final class MascotMind` — `init(settings: PreferencesStore, store: UsageStore, persistence: MascotMindPersistence = MascotMindPersistence())`, `state: MascotMindState` (private(set)), `activeGesture: MascotGesture` (private(set)), `start()`, `stop()`, `noteExpanded(now:)`

- [ ] **Step 1: Compile-gate test (sem lógica nova — o teste cobre o gate de toggle)**

Create `Tests/NotchAgentTests/DelightSoundsTests.swift` (usado também na Task 7 — aqui só o gate):

```swift
import XCTest
@testable import NotchAgent

final class DelightSoundsTests: XCTestCase {
    func testEligibilityGates() {
        XCTAssertTrue(DelightSounds.eligibility(enabled: true, reduceMotion: false, screenReader: false))
        XCTAssertFalse(DelightSounds.eligibility(enabled: false, reduceMotion: false, screenReader: false))
        XCTAssertFalse(DelightSounds.eligibility(enabled: true, reduceMotion: true, screenReader: false))
        XCTAssertFalse(DelightSounds.eligibility(enabled: true, reduceMotion: false, screenReader: true))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DelightSoundsTests`
Expected: FAIL — cannot find `DelightSounds`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/NotchAgent/Features/Delight/DelightSounds.swift` (corpo mínimo agora; síntese completa na Task 7):

```swift
import AVFoundation
import AppKit
import Foundation

/// Synthesized tick layer + the accessibility gate. No audio files.
@MainActor
public final class DelightSounds {
    public init() {}

    /// Reduce Motion freezes the puppet; VoiceOver silences the sound.
    public static func eligibility(enabled: Bool, reduceMotion: Bool, screenReader: Bool) -> Bool {
        enabled && !reduceMotion && !screenReader
    }

    public func play(_ gesture: MascotGesture) {
        // Task 7 fills the synthesis; kept silent until then.
    }
}
```

Create `Sources/NotchAgent/Features/Delight/MascotMind.swift`:

```swift
import AppKit
import Foundation
import Observation

/// The mascot's running mind: owns the persisted state, ticks every 60s,
/// receives nudges from app events and turns them into gestures — which it
/// may ignore. Everything here is gated by `settings.delightEnabled`.
@MainActor
@Observable
public final class MascotMind {
    public private(set) var state: MascotMindState
    /// The gesture the puppet is currently performing (`.none` when idle).
    public private(set) var activeGesture: MascotGesture = .none

    private var rng = SystemRandomNumberGenerator()
    private let persistence: MascotMindPersistence
    private let settings: PreferencesStore
    private weak var store: UsageStore?
    private var tickTask: Task<Void, Never>?
    private var lastTickAt = Date()
    private var lastInteractionAt = Date()
    private var isPanelOpen = false
    private var burnHigh = false
    private var previousMetrics: [ProviderID: GaugeMetric] = [:]
    private let sounds = DelightSounds()

    public init(
        settings: PreferencesStore,
        store: UsageStore,
        persistence: MascotMindPersistence = MascotMindPersistence()
    ) {
        self.settings = settings
        self.store = store
        self.persistence = persistence
        self.state = persistence.load()
    }

    public func start() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.tick()
            }
        }
    }

    public func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Called when the panel expands. First expand of the day bumps
    /// affection; other expands roll a ~20% random gesture.
    public func noteExpanded(now: Date = Date()) {
        lastInteractionAt = now
        isPanelOpen = true
        guard settings.settings.delightEnabled else { return }
        if MascotMindCore.firstExpandOfDay(state: state, dayKey: DelightSignals.dayKey(now)) {
            state.lastExpandedDay = DelightSignals.dayKey(now)
            state.affection = min(1, state.affection + DelightCatalog.affectionBump(firstExpandOfDay: true))
            react(to: .firstExpandOfDay, now: now)
        } else if Double.random(in: 0..<1, using: &rng) < 0.2 {
            react(to: .randomExpand, now: now)
        }
        saveSoon()
    }

    /// Called when the panel collapses — the mascot never performs (or
    /// makes noise) with the panel closed.
    public func noteCollapsed(now: Date = Date()) {
        lastInteractionAt = now
        isPanelOpen = false
        activeGesture = .none
    }

    /// The usage peak passed (alert cleared).
    public func notePeakPassed(now: Date = Date()) {
        guard settings.settings.delightEnabled else { return }
        react(to: .peakPassed, now: now)
        saveSoon()
    }

    private func tick() {
        guard settings.settings.delightEnabled else { return }
        let now = Date()
        let idle = now.timeIntervalSince(lastInteractionAt)

        var s = state
        MascotMindCore.evolveTick(state: &s, now: now, idleSeconds: idle, burnHigh: burnHigh)
        if let lastSeen = state.lastSeen {
            let absentDays = max(0, Int(now.timeIntervalSince(lastSeen) / 86_400))
            s.affection = max(0, s.affection - DelightCatalog.affectionAbsencePenalty(absentDays: absentDays))
        }
        state = s

        detectQuotaReset(now: now)

        if DelightSignals.crossedMidnight(previous: lastTickAt, now: now) {
            react(to: .midnight, now: now)
        }
        if idle >= 30 {
            react(to: .idleThirtySeconds, now: now)
        } else {
            let gesture = MascotMindCore.selfInitiatedGesture(state: &state, now: now, rng: &rng)
            if gesture != .none { perform(gesture) }
        }
        lastTickAt = now
        saveSoon()
    }

    private func detectQuotaReset(now: Date) {
        guard let snapshots = store?.snapshots else { return }
        var currentMetrics: [ProviderID: GaugeMetric] = [:]
        for (provider, snapshot) in snapshots {
            if let metric = GaugeMetric.from(snapshot) {
                currentMetrics[provider] = metric
            }
        }
        let resetProviders = currentMetrics.keys.filter {
            DelightSignals.quotaResetDetected(previous: previousMetrics[$0], current: currentMetrics[$0])
        }
        if !resetProviders.isEmpty {
            react(to: .quotaReset, now: now)
        }
        burnHigh = currentMetrics.values.map(\.used).max() ?? 0 >= 70
        previousMetrics = currentMetrics
    }

    private func react(to moment: DelightMoment, now: Date) {
        var s = state
        let gesture = MascotMindCore.nudge(state: &s, moment: moment, now: now, rng: &rng)
        state = s
        if gesture != .none, gesture != .ignored {
            perform(gesture)
        }
    }

    private func perform(_ gesture: MascotGesture) {
        guard isPanelOpen else { return }
        activeGesture = gesture
        let eligible = DelightSounds.eligibility(
            enabled: true,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            screenReader: NSWorkspace.shared.isVoiceOverEnabled
        )
        if eligible {
            sounds.play(gesture)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.activeGesture = .none
        }
    }

    private func saveSoon() {
        persistence.save(state)
    }
}
```

Modify `AppEnvironment.swift`:

1. Add after `let weather: WeatherStore` (line 21): `let mind: MascotMind`
2. In `init`, after `weather = WeatherStore(settings: preferences)` (line 42): `mind = MascotMind(settings: preferences, store: store)`
3. In the `store.onRestore` closure (line ~50), extend the capture list and body:

```swift
        store.onRestore = { [notifications, preferences, mind] moment in
            notifications.postRestored(moment, settings: preferences.settings)
            mind.notePeakPassed()
        }
```

4. In `bootstrap`, after `controller.show()` (line ~77), add: `mind.start()`
5. In `bootstrap`, the `NotchWindowController(...)` call gains `mind: mind`:

```swift
        let controller = NotchWindowController(
            viewModel: notchViewModel,
            store: store,
            router: router,
            spending: spending,
            weather: weather,
            mind: mind
        )
```

Modify `NotchWindowController.swift`:

1. Init signature (line 18): add `mind: MascotMind` parameter.
2. Store it: `private let mind: MascotMind` (or match the existing storage pattern — `private let weather: WeatherStore` etc.).
3. After `.environment(weather)` (line 77): `.environment(mind)`

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DelightSoundsTests`
Expected: PASS (1 teste). Then `swift build` — deve compilar com o wiring completo; se `UsageSnapshot`/`GaugeMetric` divergirem do esperado, ajustar `MascotMind` ao código real de `Sources/NotchAgent/Core/Models/Usage.swift`.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Features/Delight/MascotMind.swift Sources/NotchAgent/Features/Delight/DelightSounds.swift Sources/NotchAgent/App/AppEnvironment.swift Sources/NotchAgent/Features/NotchOverlay/Windowing/NotchWindowController.swift Tests/NotchAgentTests/DelightSoundsTests.swift
git commit -m "feat(delight): MascotMind observable com tick 60s e wiring completo no AppEnvironment"
```

---

### Task 6: Puppet — animação procedural no mascote

**Files:**
- Create: `Sources/NotchAgent/Features/Delight/MascotPuppetView.swift`
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Components/ProviderCardView.swift` (envolver o ClaudeMascot)
- Test: `Tests/NotchAgentTests/PuppetMotionTests.swift`

**Interfaces:**
- Consumes: `MascotGesture` (Task 2), `MascotMind.activeGesture` (Task 5), `Theme` (tokens existentes).
- Produces (usado pela Task 8 e pela integração visual):
  - `enum PuppetMotion` — `struct Parameters: Equatable` com `scaleY, rotationDegrees, offsetY, duration: Double`; `static func parameters(for gesture: MascotGesture) -> Parameters`
  - `struct MascotPuppetView<Content: View>: View` — `init(gesture: MascotGesture, enabled: Bool, @ViewBuilder content: () -> Content)`

- [ ] **Step 1: Write the failing test**

Create `Tests/NotchAgentTests/PuppetMotionTests.swift`:

```swift
import XCTest
@testable import NotchAgent

final class PuppetMotionTests: XCTestCase {
    func testEveryGestureHasAParameterSet() {
        for gesture in MascotGesture.allCases {
            let p = PuppetMotion.parameters(for: gesture)
            XCTAssertGreaterThan(p.scaleY, 0)
            XCTAssertGreaterThanOrEqual(p.duration, 0)
        }
    }

    func testInactiveGesturesAreStill() {
        let none = PuppetMotion.parameters(for: .none)
        let ignored = PuppetMotion.parameters(for: .ignored)
        XCTAssertEqual(none.scaleY, 1)
        XCTAssertEqual(none.rotationDegrees, 0)
        XCTAssertEqual(none.offsetY, 0)
        XCTAssertEqual(ignored.scaleY, 1)
        XCTAssertEqual(ignored.rotationDegrees, 0)
        XCTAssertEqual(ignored.offsetY, 0)
    }

    func testActiveGesturesMove() {
        let hop = PuppetMotion.parameters(for: .hop)
        XCTAssertNotEqual(hop.offsetY, 0)
        let tilt = PuppetMotion.parameters(for: .tilt)
        XCTAssertNotEqual(tilt.rotationDegrees, 0)
        let stretch = PuppetMotion.parameters(for: .stretch)
        XCTAssertNotEqual(stretch.scaleY, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PuppetMotionTests`
Expected: FAIL — cannot find `PuppetMotion`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/NotchAgent/Features/Delight/MascotPuppetView.swift`:

```swift
import SwiftUI

/// The motion table: every gesture is a small transform over the existing
/// sprite — no new art, no timeline. Reduce Motion maps everything to
/// `.none` at the call site.
public enum PuppetMotion {
    public struct Parameters: Equatable {
        public var scaleY: Double
        public var rotationDegrees: Double
        public var offsetY: Double
        public var duration: Double

        public init(scaleY: Double, rotationDegrees: Double, offsetY: Double, duration: Double) {
            self.scaleY = scaleY
            self.rotationDegrees = rotationDegrees
            self.offsetY = offsetY
            self.duration = duration
        }
    }

    public static func parameters(for gesture: MascotGesture) -> Parameters {
        switch gesture {
        case .blink: Parameters(scaleY: 0.88, rotationDegrees: 0, offsetY: 0, duration: 0.12)
        case .tilt: Parameters(scaleY: 1, rotationDegrees: 7, offsetY: 0, duration: 0.35)
        case .hop: Parameters(scaleY: 1, rotationDegrees: 0, offsetY: -8, duration: 0.4)
        case .stretch: Parameters(scaleY: 1.07, rotationDegrees: 0, offsetY: 0, duration: 0.3)
        case .nod: Parameters(scaleY: 1, rotationDegrees: 0, offsetY: 3, duration: 0.25)
        case .yawn: Parameters(scaleY: 1.04, rotationDegrees: -4, offsetY: 0, duration: 0.5)
        case .lookAtCursor: Parameters(scaleY: 1, rotationDegrees: 3, offsetY: 0, duration: 0.3)
        case .none, .ignored: Parameters(scaleY: 1, rotationDegrees: 0, offsetY: 0, duration: 0)
        }
    }
}

/// Wraps the mascot sprite and performs the active gesture as a spring
/// transform. The yawn adds a drifting "z z z". Pure decoration.
public struct MascotPuppetView<Content: View>: View {
    public let gesture: MascotGesture
    public let enabled: Bool
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(gesture: MascotGesture, enabled: Bool, @ViewBuilder content: () -> Content) {
        self.gesture = gesture
        self.enabled = enabled
        self.content = content()
    }

    public var body: some View {
        let motion = PuppetMotion.parameters(for: (reduceMotion || !enabled) ? .none : gesture)
        content
            .scaleEffect(y: motion.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(motion.rotationDegrees))
            .offset(y: motion.offsetY)
            .animation(.spring(duration: motion.duration, bounce: 0.35), value: gesture)
            .overlay(alignment: .topTrailing) {
                if gesture == .yawn, !reduceMotion, enabled {
                    Text("z z z")
                        .font(Theme.body(8, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .offset(y: -8)
                        .transition(.opacity)
                }
            }
    }
}
```

Modify `ProviderCardView.swift` — add `@Environment(MascotMind.self) private var mind` next to the existing `@Environment(UsageStore.self)` (line 12), and in `providerGlyph` replace the Claude branch:

```swift
        switch provider {
        case .claudeCode:
            MascotPuppetView(
                gesture: mind.activeGesture,
                enabled: store.settings.delightEnabled
            ) {
                ClaudeMascot(name: Self.mascotName(for: snapshot?.activeModel))
            }
            .frame(width: 48, height: 48)
```

(Check that `store.settings` is the access path used elsewhere in this file — `store.settings` is used in `metrics(_:)` as `let settings = store.settings`. ✓)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PuppetMotionTests` → PASS (3 testes). Then `swift build` (ProviderCardView deve compilar com o environment novo — o `.environment(mind)` da Task 5 já está no NotchWindowController; o PreviewData também usa ProviderCardView, então adicionar `.environment(MascotMind(settings:store:persistence:...))`… na verdade o PreviewData não precisa: `@Environment` sem valor injetado crasha em previews. Ver `Sources/NotchAgent/Core/Utilities/PreviewData.swift` — adicionar lá um mind de preview ou usar `MascotMind(settings: PreviewData.preferences(), store: PreviewData.store())`. Se os previews não forem usados em testes, apenas compilar.)

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Features/Delight/MascotPuppetView.swift Sources/NotchAgent/Features/NotchOverlay/Components/ProviderCardView.swift Tests/NotchAgentTests/PuppetMotionTests.swift
git commit -m "feat(delight): puppet procedural do mascote — tabela de movimento + spring no card"
```

---

### Task 7: Som sintetizado — DelightSounds completo

**Files:**
- Modify: `Sources/NotchAgent/Features/Delight/DelightSounds.swift`
- Test: `Tests/NotchAgentTests/DelightSoundsTests.swift` (o gate da Task 5 já existe)

**Interfaces:**
- Consumes: `MascotGesture` (Task 2).
- Produces: `DelightSounds.play(_ gesture: MascotGesture)` com síntese real.

- [ ] **Step 1: Extend the failing test**

Add to `DelightSoundsTests.swift`:

```swift
    func testPlayMapsGestureToTone() {
        // The mapping itself is a pure lookup; the audio side is covered by
        // smoke (Task 8). This test locks which gestures produce sound.
        XCTAssertNotNil(DelightSounds.tone(for: .nod))
        XCTAssertNotNil(DelightSounds.tone(for: .hop))
        XCTAssertNotNil(DelightSounds.tone(for: .stretch))
        XCTAssertNotNil(DelightSounds.tone(for: .yawn))
        XCTAssertNil(DelightSounds.tone(for: .blink))
        XCTAssertNil(DelightSounds.tone(for: .none))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DelightSoundsTests`
Expected: FAIL — `DelightSounds` has no member `tone`.

- [ ] **Step 3: Write minimal implementation**

Replace `DelightSounds.swift` with:

```swift
import AVFoundation
import AppKit
import Foundation

/// Synthesized tick layer + the accessibility gate. No audio files.
@MainActor
public final class DelightSounds {
    public struct Tone: Equatable {
        public let frequency: Double
        public let duration: Double
        public let volume: Float

        public init(frequency: Double, duration: Double, volume: Float) {
            self.frequency = frequency
            self.duration = duration
            self.volume = volume
        }
    }

    private let engine = AVAudioEngine()

    public init() {}

    /// Reduce Motion freezes the puppet; VoiceOver silences the sound.
    public static func eligibility(enabled: Bool, reduceMotion: Bool, screenReader: Bool) -> Bool {
        enabled && !reduceMotion && !screenReader
    }

    /// Which gestures make noise — silent gestures (blink, lookAtCursor)
    /// stay silent: the sound layer is for confirmations, not chatter.
    public static func tone(for gesture: MascotGesture) -> Tone? {
        switch gesture {
        case .nod: Tone(frequency: 880, duration: 0.18, volume: 0.15)
        case .hop: Tone(frequency: 660, duration: 0.14, volume: 0.13)
        case .stretch: Tone(frequency: 300, duration: 0.12, volume: 0.10)
        case .yawn: Tone(frequency: 240, duration: 0.20, volume: 0.09)
        default: nil
        }
    }

    public func play(_ gesture: MascotGesture) {
        guard let tone = Self.tone(for: gesture) else { return }
        playTone(tone)
    }

    /// One synthesized note: sine with soft attack and exponential decay,
    /// played on a throwaway player node and detached when done.
    private func playTone(_ tone: Tone) {
        let sampleRate = 44_100.0
        let frameCount = Int(tone.duration * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let env = Float(exp(-6.0 * t / tone.duration)) * Float(min(1, t / 0.01))
            samples[i] = Float(sin(2 * .pi * tone.frequency * t)) * env * tone.volume
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil) { [weak self] in
            Task { @MainActor in self?.engine.detach(player) }
        }
        if !engine.isRunning {
            try? engine.start()
        }
        player.play()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DelightSoundsTests`
Expected: PASS (2 testes). Full: `swift test` — 0 falhas.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Features/Delight/DelightSounds.swift Tests/NotchAgentTests/DelightSoundsTests.swift
git commit -m "feat(delight): síntese de tons AVAudioEngine para os gestos sonoros"
```

---

### Task 8: Tinta por hora do dia + integração no painel

**Files:**
- Create: `Sources/NotchAgent/Features/Delight/TimeTintView.swift`
- Modify: `Sources/NotchAgent/Features/NotchOverlay/Views/NotchContainerView.swift` (camada de tinta + `noteExpanded`)

**Interfaces:**
- Consumes: `DelightSignals.TimeTintKey` + `tintColor(for:)` (Task 3), `MascotMind.noteExpanded` (Task 5), `preferences.settings.delightEnabled` (Task 1), `preferences.settings.weatherEnabled` (existente), `NotchViewModel.isExpanded` (existente).
- Produces: `struct TimeTintView: View` — `init(key: DelightSignals.TimeTintKey)`

- [ ] **Step 1: Write the failing test**

Create `Tests/NotchAgentTests/TimeTintTests.swift`:

```swift
import XCTest
@testable import NotchAgent

final class TimeTintTests: XCTestCase {
    func testTintOnlyAppliesWithoutWeather() {
        // The layer's visibility rule is a pure predicate on the two toggles.
        XCTAssertTrue(TimeTintVisibleRule.evaluate(delightEnabled: true, weatherEnabled: false))
        XCTAssertFalse(TimeTintVisibleRule.evaluate(delightEnabled: true, weatherEnabled: true))
        XCTAssertFalse(TimeTintVisibleRule.evaluate(delightEnabled: false, weatherEnabled: false))
        XCTAssertFalse(TimeTintVisibleRule.evaluate(delightEnabled: false, weatherEnabled: true))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TimeTintTests`
Expected: FAIL — cannot find `TimeTintVisibleRule`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/NotchAgent/Features/Delight/TimeTintView.swift`:

```swift
import SwiftUI

/// Pure visibility rule for the time-of-day wash — weather wins; without
/// weather, the wash only shows when the delight layer is on.
public enum TimeTintVisibleRule {
    public static func evaluate(delightEnabled: Bool, weatherEnabled: Bool) -> Bool {
        delightEnabled && !weatherEnabled
    }
}

/// Subtle time-of-day wash over the panel, behind everything: cold at
/// night, warm at dusk. Never draws when the weather sky is on.
public struct TimeTintView: View {
    public let key: DelightSignals.TimeTintKey

    public init(key: DelightSignals.TimeTintKey) {
        self.key = key
    }

    public var body: some View {
        LinearGradient(
            colors: [Color(nsColor: DelightSignals.tintColor(for: key)), .clear],
            startPoint: .top,
            endPoint: .center
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
```

Modify `NotchContainerView.swift`:

1. Add `@Environment(MascotMind.self) private var mind` next to the other `@Environment` declarations (top of the struct).
2. Insert the wash right AFTER the panel fill (after line 34, before the sky):

```swift
                // Time-of-day wash: only when the weather sky is OFF — the
                // sky already owns the ambience; the wash fills its absence.
                if TimeTintVisibleRule.evaluate(
                    delightEnabled: preferences.settings.delightEnabled,
                    weatherEnabled: preferences.settings.weatherEnabled
                ) {
                    TimelineView(.periodic(from: .now, by: 300)) { timeline in
                        TimeTintView(key: DelightSignals.timeTint(at: timeline.date))
                            .clipShape(panelShape)
                            .transition(.opacity)
                    }
                    .accessibilityHidden(true)
                }
```

3. Note expands for the mind (add after the `.animation(...)` modifier on the ZStack frame):

```swift
            .onChange(of: viewModel.isExpanded) { _, expanded in
                if expanded {
                    mind.noteExpanded()
                } else {
                    mind.noteCollapsed()
                }
            }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TimeTintTests` → PASS (1 teste). Full: `swift test` — suíte completa 0 falhas. Then `swift build`.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchAgent/Features/Delight/TimeTintView.swift Sources/NotchAgent/Features/NotchOverlay/Views/NotchContainerView.swift Tests/NotchAgentTests/TimeTintTests.swift
git commit -m "feat(delight): tinta por hora do dia no painel + noteExpanded no expand"
```

---

### Smoke final (após Task 8)

```bash
pkill -9 -x NotchAgent; sleep 1; ./Scripts/make-app.sh
rm -rf /Applications/NotchAgent.app && cp -R dist/NotchAgent.app /Applications/ && open /Applications/NotchAgent.app
```

Checklist manual:
1. Expandir o painel várias vezes → mascote eventualmente pisca/pula (~20% dos expands).
2. Settings → desligar "Efeitos e reações do painel" → painel sóbrio imediatamente (sem gesto, som, tinta).
3. Desligar clima e ligar efeitos → tinta por hora do dia visível no fundo.
4. `~/Library/Application Support/NotchAgent/mascot-mind.json` existe após alguns minutos e muda entre sessões.
5. Reduzir Motion do macOS → sem animação; VoiceOver → sem som.
