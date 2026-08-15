# Changelog

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
