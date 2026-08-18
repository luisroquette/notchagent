# Changelog

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
