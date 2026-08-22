# Changelog

## 3.5.3 — 2026-08-22

Critical regression fix. Hours after 3.5.2 shipped, the panel would
force-expand and play the "full tank" celebration every few minutes with
no real quota reset — caused by 3.5.2 itself.

### Fixed

- **Restore-moment celebration no longer fires repeatedly with no real
  reset.** 3.5.2 changed Codex's weekly cap from always-exhausted to
  reflecting the model with the most headroom — which means
  `GaugeMetric.isWeekly` for Codex can now legitimately flip between
  refreshes (session headline vs weekly headline), instead of being
  permanently `true` as before. The restore-celebration tracking is keyed
  per provider+window on purpose (a flipping gauge must not suppress a
  real alert), but a provider whose window ITSELF flips minted a "new"
  key on every flip, and the other key's stale fired state read as a
  fresh reset on the very next flip back — celebrating (and
  force-expanding the panel) every few minutes. Fixed with a 20-minute
  per-provider cooldown on the celebration; a genuine recovery still
  celebrates.

## 3.5.2 — 2026-08-21

Codex quota-accuracy release. The Codex card was misreporting availability
whenever a single model's weekly cap ran out, even though the account could
still use other Codex models normally — confirmed empirically by hitting a
429 on one model and switching to another without any wait.

### Fixed

- **Codex headline now reflects the model with the most headroom, not the
  least.** Codex models are independent quota pools (unlike Claude's single
  shared account) — exhausting one model's weekly cap never blocks the
  others. The old rule picked the worst model seen locally as the headline
  number, painting the whole card red/exhausted over a single model. The
  per-model breakdown still lists every model, exhausted ones included —
  nothing is hidden, the headline just stops overstating how blocked you
  are.
- The exhausted-quota hint now names the specific model ("gpt-5.3-codex-spark's
  weekly cap is exhausted…") instead of a generic "every model seen locally
  is exhausted" message that read as the whole Codex account being blocked.
- Compact notch view: the top row (provider + window label) was clipped by
  the system menu bar on notched displays — the stacked line boxes reserved
  more vertical space than the physical notch height allows. Fixed without
  changing font sizes.

## 3.5.1 — 2026-08-20

Desk pairing release. The wire protocol formally declares 1.3 — the additive
`currentHour` fields the app has sent since 3.4.0 now carry their own minor
version — and the bundle version tracks the build number again.

### Changed

- Desk wire protocol declared 1.3 (additive `currentHour` /
  `currentHourElapsedFraction` snapshot fields; pairs with Desk firmware
  0.8.0, and stays compatible with 1.2 hosts and firmware).
- Distribution: ZIP and DMG are now signed with **Developer ID** and
  **notarized by Apple** (stapled ticket; Gatekeeper reports
  `Notarized Developer ID`). Sparkle appcast announces 3.5.1, Homebrew
  Cask updated, /Applications install refreshed.

### Fixed

- `CFBundleVersion` now tracks `BUILD_NUMBER` (8 for this release), ending
  the stale bundle-version drift on signed ZIP installs.
- Install section links to the signed ZIP release instead of a stale path.

## 3.5.0 — 2026-08-20

The honest-gauge release. The quota window hierarchy became a locked
contract, the Now page never varies its layout, and the weather ambience
became a minimal 8-bit strip.

### Added

- Structural contract guards that READ THE SOURCE CODE: the quota window
  hierarchy (BLOCKED > weekly exhausted > 5h session > weekly partial) and
  the invariant card layout are locked by tests that fail on any physical
  reordering or adaptive-layout reintroduction.
- Pre-push hook runs the full test suite before every push.
- Procedural 8-bit weather glyphs for all 12 WMO condition bands, day and
  night, rendered in a minimal strip at the top of the panel.

- Delight engine: the Claude mascot is alive — contextual animations across
  9 contexts (greeting, calm, tense, drowsy, playful, relief, celebration,
  midnight, poke) with persistent round-robin variety. No randomness: every
  animation belongs to a context.
- Ambient presence: idle breathing, eyes blinking every 2.5–5.5s, head
  follows the cursor, pokes always get an annoyed reaction.
- Context depth: celebration confetti on quota reset, compound yawn with
  "z z z" at midnight, anticipation + follow-through on most gestures,
  squash/stretch coupled to motion.
- The four family mascots on the Claude Models page share the same life;
  only the active model's mascot acts out global events.
- The runner game revives with a bounce when the quota resets.

### Changed

- The Now page card layout is INVARIANT: the 5h session window always sits
  above the weekly window, for Claude and Codex, in every quota state. The
  adaptive layouts (token headline, weekly override badge) were removed.
- Weather: the full-panel sky and precipitation layers (bright blue
  gradient, large sun) were removed; weather lives only as the top strip.
- The OpenAI knot now has eyes — its measured dash notches — with a
  per-sprite face patch color.
- Panel blocks are liquid glass now: translucent gradient, 1px glass edge,
  specular rim and layered shadows — replaces the flat white cards.
- Mascot and runner animations render through Canvas + TimelineView(.periodic):
  view transform modifiers and display-link schedules proved inert in this
  panel.

### Fixed

- Exhausted weekly cap always beats the 5h session gauge — an official
  (quota-backed) fresh session can no longer paint "100% left" in green
  while the weekly reads 0% (wings, runner, alerts, cards).
- A BLOCKED session can never print "No burn right now — safe until the
  reset." next to the runner's GAME OVER.
- The burn page headline and verdict now follow the shared gauge, never
  the raw session percent.
- The GPT glyph no longer washes out under the old specular overlay.
- Mascot sprite keeps its native aspect ratio in the square slot.

## 3.4.2 — 2026-08-18

### Changed

- Claude mascots are now extracted verbatim from the approved V7 mockup —
  one PNG sprite per family, shipped in `Resources/Mascots`, no procedural
  interpretation. Same for the OpenAI glyph.

## 3.4.1 — 2026-08-18

### Changed

- Model mascots redrawn to the approved V7 design: smooth bean/egg body with
  two big round eyes, no mouth, no arms — one shape for every family.
- OpenAI glyph reworked: thin interlocking loops instead of the blocky petals
  that read as a gear at row size.

## 3.4.0 — 2026-08-18

### Added

- Model pages mascot system: faithful Anthropic-style pixel mascots per
  family (Haiku/Fable happy dot-eyes, Sonnet/Opus neutral dash-eyes) and a
  single OpenAI knot glyph on every OpenAI model row.
- "TOP MODEL" callout on the Claude Models page.

### Changed

- Claude Models page: four cards replaced by compact rows — mascot, name,
  status, 8-bit segmented quota/token-share meter, tokens and cost.
- Desk snapshot now carries current-hour progress (`currentHour` +
  `currentHourElapsedFraction`) so the Desk can render the still-filling bar.
- Page-swap animation is a slower glide instead of a spring snap.
- Claude probe logs up to 300 chars of the error body when rate-limit
  headers are missing, so rejected probes explain themselves.
- Separated the NotchAgent desktop software from the physical NotchAgent Desk
  product. Hardware, firmware, protocol, compatibility, and factory work now
  lives in `luisroquette/notchagent-desk`.

### Deprecated

- The local `firmware/notchagent_desk` tree is retained only to reproduce the
  signed 3.1.2 release and will be removed in the next major app release.

## 3.3.0 — 2026-08-16

### Added

- `DeskSnapshot` now carries `dominantModelShortName` and `modelAlternates`
  (short name + price ratio per Claude tier), reusing the existing
  `burnHistory` series so the physical NotchAgent Desk can render the same
  multi-model burn projection as the macOS app's BURN chart. Wire protocol
  minor version 1.1 → 1.2 — additive only, older Desk firmware ignores the
  new fields safely.

## 3.2.0 — 2026-08-16

### Added

- The BURN chart now projects quota burn for the other Claude model tiers
  (Haiku, Sonnet, Opus, Fable) alongside the model actually in use, using
  each tier's real per-token pricing — answers "would I last longer on a
  different model" at a glance. The model with the most tokens spent in the
  current 5h session (Haiku/Sonnet/Opus only — Fable is metered on a
  separate quota pool and is never treated as dominant) stays the
  highlighted line; the other three render as thinner alternates with a
  direct end-of-line label instead of a separate legend row, so identifying
  a line doesn't require looking away from it.
- Per-model line colors validated for colorblind and normal-vision
  contrast against the existing highlight color; the validation numbers
  and remaining known-tight pairs are documented in-code rather than
  asserted without evidence.

### Fixed

- `PricingTable` priced Claude Opus 5 and Fable 5 identically through a
  stale generic fallback; Fable 5 is the more expensive tier and now has
  its own entry.
- The chart's end-of-line label could detach up to 44px from its actual
  line endpoint in the common case; only the label text now clamps to stay
  on-canvas, the marker dot stays anchored to the true data point.
- The "NOW" label's collision-avoidance seed used the wrong y-coordinate
  (13px off), which routinely failed to prevent the overlap it existed to
  prevent.
- A degenerate canvas height during the notch panel's expand/collapse
  animation could trap on an invalid `ClosedRange` construction; the chart
  now clamps defensively.
- `SessionUsage`'s new `usedPercentIsFromQuota` field was briefly
  non-optional, which would have broken decoding of any previously
  persisted `snapshots.json` on upgrade; corrected to optional with a
  regression test covering a payload missing the key.
- Redundant `visibleSamples`/polyline recomputation (up to 7x per redraw
  during active hover) consolidated to a single computation per frame.

### Security

- Full data-flow review of the new code (transcript parsing → provider →
  projection → rendering) found no new network/credential surface, no
  force-unwraps, and no unbounded work driven by transcript content — the
  alternate-model candidate list is a fixed 4-entry array, not derived from
  file contents.

## 3.1.3 — 2026-08-15

### Added

- Per-model quota breakdown now shows inline on the compact home card
  (previously only on the dedicated model detail pages), sorted by whichever
  model still has the most headroom — the headline number already answers
  "am I in trouble", this answers "where can I still work". When every known
  model is exhausted, shows a hint pointing at the account's own usage page
  instead of a wall of uninformative 0%s.

### Fixed

- Codex: the weekly quota headline could show room on one model's cap while
  a different model's weekly cap was actually exhausted, because a single
  API response only ever reports one model's scope at a time. Recovers
  every model's own weekly cap across recently-scanned rollouts and always
  surfaces whichever has the least headroom as the headline number.
- Codex: named quotas are now keyed by model — `resetsAt` is recomputed
  fresh on every response and isn't a stable identity, and `limitName` is
  null on every locally-observed event; both fragmented or hid real scopes.
  Expired scopes (past their own reset time) are also dropped so they can
  no longer clutter the breakdown with stale readings.
- Claude: Fable 5's quota — metered separately from the shared
  Haiku/Sonnet/Opus pool — is now tracked and surfaced independently
  instead of sharing a single cache with the other probed models.
- Claude: corrected a stale `claude-opus-4-8` model ID in the quota probe
  rotation to `claude-opus-5`, which was causing every Opus health/quota
  probe to fail outright.

## 3.1.2 — 2026-08-14

- Adds the PT/EN interactive visual setup guide directly to Desk settings.
- Keeps Codex installation on the official OpenAI documentation while the
  product walkthrough covers download, USB connection, authentication, and activation.

## 3.1.1 — 2026-08-14 (Desk Beta 1)

- Adds NotchAgent Desk automatic USB discovery, local usage mirroring, hardware
  telemetry, safe diagnostics, signed recovery packaging, and reliability gates.
- Desk mirroring and the optional Anthropic quota probe are off by default and
  require separate explicit consent.
- Setup now requires a successful Claude Code or Codex read from the current app
  launch; stale persisted snapshots and local read failures cannot enable Desk.
- Incompatible firmware and provider read failures open recovery controls
  automatically, with improved VoiceOver grouping.
- Adds explicit Codex install, authentication, first-session, and ready states
  with official sign-in, PT/EN guidance, automatic refresh, and no credential access.
- Fixes Developer ID recovery by isolating the bundled PyInstaller flasher's
  library-validation entitlement while keeping Hardened Runtime on the app.

## 3.0.0 — 2026-07-30

NotchAgent's second generation, now also focused on financial monitoring of
API accounts.

### Discontinuations

- The "AgentMeter" iOS/watchOS companion was discontinued and removed from
  the repository. API account financial monitoring now lives only in the Mac
  app.

### API monitoring

- Generic multi-account registration per provider, with credentials isolated
  in the macOS Keychain and separate web sessions per account.
- BRL financial dashboard with **Window spend**, **Current balance** and
  **Monthly plan**, never mixing top-ups, subscriptions and quotas.
- Integrations for Anthropic API, OpenAI, DeepSeek, OpenRouter, Google/Gemini,
  xAI, ElevenLabs, Firecrawl, twitterapi.io, and multiple X/Twitter projects.
- Claude/Claude Code, ChatGPT, Google AI and Firecrawl subscriptions kept
  separate from billed API spend.

### Precision and refresh

- Source recorded per field: official API, official portal, manual value, or
  proportional estimate.
- API/portal reconciliation with explicit tolerances; discrepancies leave the
  card partial instead of showing a value as confirmed.
- 30-day default window, Google on its official 28-day window, and
  calendar-month labeled explicitly when the provider requires it.
- Official BRL values preserved without reconversion; USD converted at the
  Central Bank's current PTAX rate.
- Per-card individual refresh, forced cache invalidation, and protection
  against stale responses overwriting fresh reads.
- The 30-day consumed total now explains on the card when an account is
  excluded for sharing a billing scope with one already counted, instead of
  disappearing with no explanation.
- A cost estimate for a model not recognized in the pricing table stopped
  counting as a verified US$0 — it's excluded from the estimate now, not
  zeroed out.

### Interface and operation

- Scrollable list with every provider, expandable details, and
  drag-to-reorder.
- Visible states: refreshing, updated, stale, partial, and error.
- Fixed the vertical gesture that was wrongly changing the notch page.
- Increased the API screen's typography — labels and values were between
  4.9pt and 6.5pt, illegible even on the 660pt-wide expanded panel.

### Security and distribution

- Exportable diagnostic with no credentials, cookies, names, IDs, or amounts.
- Public audit, `pre-push` hook, and CI workflow block secret patterns and
  personal identifiers.
- Bundle signing configurable per environment, with no personal certificate
  hardcoded in the code.
- `graphify-out` removed from Git for replicating generated code and data.

### Quality

- 206 automated tests passing, including financial integrity, cache,
  persistence, security, scroll, and read-only E2E for configured accounts.
- Tests and release builds run with paid probes disabled.

## 1.0.0 — 2026-07-14

First complete version.

### Core
- Plugin-like providers: Claude Code (transcripts + official API quota probe), Codex (exact rate limits from rollouts, windows classified by duration), Gemini CLI (activity; declared tokens unavailable).
- Central scheduler with concurrent refresh, per-file parse cache, JSON persistence (snapshots + 30-day history), refresh on wake.
- A single product semantic: **% of limit left** (fuel tank) across the whole UI.

### Notch
- Overlay with selective hit-testing (click-through outside the shape), geometry re-detected on screen/space/wake changes, notch-less fallback pill.
- Compact: Claude on the left, Codex on the right, with name + window (5H/WK) + % left + micro-gauge.
- Expanded: 4 pages (NOW / BURN / RHYTHM / MODELS), trackpad side-scroll, sliding transitions, haptics, Esc to close, live countdowns.
- Escalating alerts at 25/15/10/5% left with a progressively more severe animated takeover; 5% requires a click; a matching system notification fires too.
- "Retro hardware gauge" design system: black + coral, SF Rounded heavy numerals, segmented gauges, a procedural pixel-art mascot that reacts to quota.

### Distribution
- `Scripts/make-app.sh`: a complete `.app` built from SwiftPM (Info.plist, code-generated `.icns` icon, ad-hoc signing).
- Launch at login (SMAppService) and notifications — enabled in the bundle.

### Quality
- 52 tests (parsers with real fixtures, aggregator, thresholds, burn rate, pricing, geometry, end-to-end integration per provider).
