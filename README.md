# NotchAgent

**The fuel gauge for your AI agents, living in your MacBook's notch.**

> **This is the desktop software repository.** The physical ESP32-S3 product,
> firmware, USB protocol, compatibility matrix, and factory contracts now live
> in [`luisroquette/notchagent-desk`](https://github.com/luisroquette/notchagent-desk).
> Product pages: [NotchAgent app](https://notchagent.app) ·
> [NotchAgent Desk](https://cfgauss.com.br/t/notchagent-desk-shop).

<p align="center">
  <a href="https://notchagent.app"><img src="https://img.shields.io/badge/website-live-FF654F?style=flat-square" alt="NotchAgent website" /></a>
  <a href="https://github.com/luisroquette/RocketLabs"><img src="https://img.shields.io/badge/RocketLabs-flagship%20project-7C5CFC?style=flat-square" alt="RocketLabs flagship project" /></a>
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/version-v3.5.2-38D6C7?style=flat-square" alt="Version v3.5.2" /></a>
  <a href="#install"><img src="https://img.shields.io/badge/install-notarized%20DMG-F3B85A?style=flat-square" alt="Install the notarized DMG" /></a>
</p>

**Current version: 3.5.2** · Desk protocol 1.3 · pairs with Desk firmware 0.8.0 · released 2026-08-21 · [version history](CHANGELOG.md)

A native macOS menu-bar + notch overlay for Claude Code/Codex quotas and
financial monitoring of external API accounts. It shows provider-reported
spend, balance, plans and quotas with explicit sources and time windows —
local-first, no backend, no telemetry. Swift 6 + SwiftUI/AppKit, zero Electron.

**Windows preview (build from source)** — a .NET 8 + Avalonia system-tray
companion is under validation. It is not yet offered as a signed installer or
as equivalent to the macOS release. See [`windows/README.md`](windows/README.md)
for the implemented feature set, build instructions, and current limits.

**NotchAgent Desk Beta 1** consumes the app's same local-first state on a
Guition JC4832W535 ESP32-S3 touch display over USB. The hardware source of
truth is [`notchagent-desk`](https://github.com/luisroquette/notchagent-desk).
This repository retains the 3.1.2 integration snapshot temporarily so the
signed release remains reproducible; new hardware work belongs there.

Beta 1 adds automatic device identity, visible firmware/protocol/health,
sanitized diagnostics, a hash-verified local recovery updater, and repeatable
reconnect/soak-test gates. No device telemetry leaves the Mac.
See the [live setup guide](https://cfgauss.com.br/t/notchagent-instalar-pagina),
[Desk BOM](https://github.com/luisroquette/notchagent-desk/blob/main/docs/BOM.md),
and [compatibility matrix](https://github.com/luisroquette/notchagent-desk/blob/main/COMPATIBILITY.md).

![The compact notch bar: Claude on the left wing, Codex on the right](docs/img/notch-compact.png)

![Hover the notch to expand the gauge panel](docs/img/notch-panel.gif)

| NOW — 5h session above weekly, always | BURN — nothing can burn once the window is gone |
|---|---|
| ![NOW page](docs/img/now-cards.png) | ![BURN page: 5h exhausted](docs/img/burn-5h-exhausted.png) |

| BURN — weekly cap blocks the session | RHYTHM — when do you burn? |
|---|---|
| ![BURN page: weekly blocked](docs/img/burn-weekly-blocked.png) | ![RHYTHM page](docs/img/rhythm.png) |

| MODELS — Claude family, live probe | MODELS — OpenAI, per-model weekly caps |
|---|---|
| ![Claude models page](docs/img/claude-models.png) | ![OpenAI models page](docs/img/openai-models.png) |

| Dashboard — active session | Settings |
|---|---|
| ![Dashboard session](docs/img/dashboard-session.png) | ![Settings](docs/img/settings.png) |

![Low-fuel alert: an escalating takeover fires at 25/15/10/5% left, in light theme here](docs/img/alert-almost-empty.png)

## Install

**Download page: [notchagent.app](https://notchagent.app)** — free, open source, one click.

**Notarized DMG** (recommended, no Terminal):

> Both the DMG and the ZIP below are signed with Developer ID and
> notarized by Apple (stapled ticket, Gatekeeper: Notarized Developer ID).

1. Download [`NotchAgent-3.5.2.dmg`](https://cfgauss.com.br/t/notchagent-download-dmg).
2. Open the DMG and drag **NotchAgent** to **Applications**.
3. Open NotchAgent and follow the guided setup.

The DMG's published SHA-256 is
`71fc4d23580124bfa41040643abbde39a2c9ee73c44f8ff9a340689f11a9227d`.

**Homebrew** (developer channel):

```bash
brew install --cask luisroquette/tap/notchagent
open /Applications/NotchAgent.app
```

**Or download the signed ZIP** from [v3.5.2](../../releases/tag/v3.5.2), unzip it,
and move `NotchAgent.app` to `/Applications`:

```bash
open /Applications/NotchAgent.app
```

The 3.5.2 ZIP is signed with **Developer ID and notarized by Apple**
(stapled ticket, Gatekeeper verifies it as `Notarized Developer ID`). Its
published SHA-256 is
`a4a40e2c446200e65e07cdb8c95f7866648997921fd5590b664e14c5e9252268`.

**Or build from source** (Xcode 15+ / Swift 6 toolchain):

```bash
git clone https://github.com/luisroquette/notchagent.git && cd notchagent
./Scripts/audit-public-release.sh
git config core.hooksPath .githooks
./Scripts/make-app.sh && open dist/NotchAgent.app
```

`make-app.sh` uses the first local Apple Development identity. Override it with
`NOTCHAGENT_SIGN_IDENTITY`; without an identity it falls back to ad-hoc signing.

> **Why trust it?** API credentials stay in the macOS Keychain, portal sessions
> use isolated WebKit profiles, and diagnostics remove credentials, identity and
> financial amounts. Monitoring is opt-in per account. The optional Claude quota
> probe is the only feature that sends a paid one-token model request and can be
> disabled in Settings.

---

## The product

**The question NotchAgent answers at all times: "how much of my limit is left?"**

- **Compact notch** — Claude on the left wing, Codex on the right: name, `% LEFT` for the window (5H or WK) colored by state, a micro-gauge that drains like a fuel tank.
- **Expanded panel** (hover to expand, click to pin, **trackpad side-scroll switches pages**, Esc closes) with a minimal 8-bit weather strip on top and 4 pages:
  - **NOW** — per-provider cards with an INVARIANT layout: the 5h session window always above the weekly window (percent, segmented gauge, "RESETS • 16:30" + a live countdown, tokens/estimated cost, burn verdict, health pills). An exhausted weekly can never hide or swap a window.
  - **BURN** — one 5h-window chart per provider: actual usage (coral line) + dotted projection at the current pace + a verdict like "runs out 16:40 (in 1h 32m)". An exhausted window shows "nothing can burn" — never a false "safe until reset".
  - **RHYTHM** — 24 bars by local hour (today/7 days), current hour highlighted.
  - **MODELS** — Claude family and OpenAI models with a live probe (`OK 0.9s` / `Limited` / `Error`, 1 model per cycle) + per-model usage and cost from transcripts.
- **Escalating alerts at 25/15/10/5% left** — an animated notch takeover that gets more severe as the window runs out (amber pulse → red alarm with a shaking mascot at 5%, dismissed only by clicking), plus a matching system notification. One trigger per threshold per window, re-armed on reset.
- **Menu bar** — `% left` up top + a popover with a per-provider summary and controls.
- **Dashboard** — history (Swift Charts), hourly rhythm, daily breakdown, event log.
- A graceful fallback on notch-less displays (a floating pill) and a procedural pixel-art mascot as the visual signature.

## Run / Package

```bash
swift run                          # development (menu bar + overlay live)
swift test                         # unit + integration test suite
./Scripts/audit-public-release.sh  # blocks secrets and personal IDs
./Scripts/make-app.sh              # builds a local dist/NotchAgent.app for development
open dist/NotchAgent.app
```

The bundle enables: launch at login (SMAppService), system notifications, and
persistent Keychain consent. `project.yml` (XcodeGen) exists for anyone who
prefers an `.xcodeproj`.

## Data: what's real, what's estimated

| Source | Real | Estimated |
|---|---|---|
| **Anthropic probe** (optional, ~1 token/min) — `anthropic-ratelimit-unified-*` headers via Claude Code's local OAuth token | Official 5h/7d %, resets, `allowed/warning/rejected` status, limiting window, per-model health | — |
| **Claude transcripts** `~/.claude/projects/**/*.jsonl` | Tokens (input/output/cache), per-message model, 5h blocks, hourly rhythm | Cost (public table in `PricingTable.swift`) |
| **Codex rollouts** `~/.codex/sessions/**` | Exact % per window (classified by `window_minutes` — weekly-only plans like Spark are detected), resets, plan, tokens | Cost |
| **Gemini CLI** `~/.gemini/tmp/*/logs.json` | Prompts/sessions/last activity | Tokens don't exist on disk — the app declares that, it never invents them |

OAuth token: `CLAUDE_CODE_OAUTH_TOKEN` → `~/.claude/.credentials.json` →
Keychain (macOS consent prompt). Never logged; never leaves the machine except
to `api.anthropic.com`. Can be turned off in Settings (manual budgets become
the fallback).

## Configure API accounts

1. Open **Settings → API Accounts**.
2. Click **+** and choose the service.
3. Save the credential to the Keychain, or use **Connect account**.
4. Confirm the source, window, and read status on the card.

The repository ships with no predefined accounts. Names, projects, keys,
cookies, history and personal amounts stay out of Git. See
[`docs/API_ACCOUNT_MONITORING.md`](docs/API_ACCOUNT_MONITORING.md).

## Stop finding out about an API cost blowout only when the invoice lands

If you have API keys scattered across several providers — sometimes more than
one account on the same provider — no native dashboard shows it all together.
Version 3.0 turned NotchAgent into an API financial dashboard too:

- **Never mix up which key is which** — add as many accounts as you want,
  including two on the same provider, each with isolated credentials and
  session.
- **Spend, balance and plan, never mixed** — each card separates **Window
  spend**, **Current balance** and **Monthly plan**; a top-up is never
  mistaken for spend.
- **Trust the number you're looking at** — every value shows its own origin:
  official API, official portal, manual entry, or a proportional estimate —
  never a made-up number presented as a fact.
- **A fair comparison across providers** — 30 rolling days by default; Google
  AI Studio keeps its official 28-day window; calendar-month is labeled
  explicitly when it's the only window a provider offers — never mixing
  different windows into one total.
- **Secure by default** — per-account refresh, protection against stale data
  overwriting a fresh read, a sanitized exportable diagnostic, and USD/BRL
  conversion at the Brazilian Central Bank's current PTAX rate.

Covers Anthropic API, OpenAI, DeepSeek, OpenRouter, Google/Gemini, xAI,
ElevenLabs, Firecrawl, twitterapi.io, and multiple X/Twitter projects —
subscriptions like Claude/Claude Code and ChatGPT always show up separate
from API spend.

## Version control and releases

The project uses [Semantic Versioning](https://semver.org/):

- **MAJOR**: a breaking change or a new generation of the product.
- **MINOR**: a backward-compatible feature.
- **PATCH**: a backward-compatible fix.

`VERSION` is the single source of truth for the version number.
`Scripts/make-app.sh` reads this file when packaging; `Resources/Info.plist`,
README and CHANGELOG must all match the same number. Before any release:

```bash
./Scripts/check-version.sh
./Scripts/audit-public-release.sh
NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test
```

Every version must add an entry at the top of `CHANGELOG.md` with the date,
what's new, fixes, security, and validation.

The complete release contract is in [`VERSIONING.md`](VERSIONING.md). Hardware
and firmware versions are owned by the separate Desk repository and never reuse
the app version number.

## Architecture

```
Providers (plugin) ─▶ UsageSnapshot ─▶ UsageStore (@Observable) ─▶ Notch · MenuBar · Dashboard
      ▲ FileScanCache/actors    ▲ StatusAggregator + ThresholdAlerts + BurnRate (pure, tested)
RefreshScheduler ───────────────┴─▶ SnapshotStore/HistoryStore (JSON, 30d)
                                       └─▶ sanitized DeskSnapshot ─USB─▶ NotchAgent Desk
```

- **Overlay**: a borderless, non-activating `NSPanel` (`.statusBar` level, all Spaces, above fullscreen) with a custom `hitTest` — only the visible shape captures clicks; the rest of the transparent window is click-through.
- **Interactions**: local `scrollWheel` (paging) and `keyDown` (Esc) monitors, haptics on page/pin, `TimelineView` for live countdowns.
- **New provider** = one folder with a pure parser + `UsageProvider` + fixture; the UI adapts to the declared capabilities.

## Precision model (what's exact, what's estimated)

**Exact (official source):**
- Claude's quota **percentages** come from the API's `anthropic-ratelimit-unified-*` headers — they're **account-wide**: they cover the Claude Code CLI, the Desktop app, and claude.ai web and mobile. The same holds for Codex's percentages (local rollouts reflect account state).
- Reset times and status (`allowed/warning/rejected`) — same.

**Counted locally (aligned to the official window):**
- Claude's tokens and costs sum **all** local transcript sources: the CLI (`~/.claude/projects`) **and the Desktop app's agent-mode sessions** (`~/Library/Application Support/Claude/local-agent-mode-sessions`).
- Session/week totals use **the same window as the percentage** (start = official reset − 5h/7d), not "the last N wall-clock hours."
- Codex's session sums **every rollout active within the window** (concurrent sessions never undercount).

**Known margins (measured, not estimated):**
- *Chat* conversations (Desktop/web) don't produce a local transcript → they count toward the **%**, not toward local tokens.
- Hourly buckets ⇒ window-boundary precision of ±1h on tokens (the % is unaffected).
- Retry duplicates across files: **0.18%** measured inflation on this base (dedup is per-file).
- Costs use a public pricing table (`PricingTable.swift`) — subscription plans don't bill per token; treat this as an order of magnitude.

## Known limitations

- Notch geometry is inferred (`safeAreaInsets` + auxiliary areas) — there's no official API; a fallback pill covers Apple changes.
- Costs are estimates from a public table; subscription plans don't bill per token.
- The 3.5.2 ZIP and DMG are Developer ID signed and notarized. The Desk hardware gates (24-hour physical soak, pilot evidence) apply to the Desk product, not the app distribution.
- Local source builds are not the notarized release; they use the first available Apple Development identity unless `NOTCHAGENT_SIGN_IDENTITY` selects another identity.
- `Limited` on the MODELS page reflects the account's unified rate limit at probe time, not the model itself being unavailable.

## Distribution status

- [x] NotchAgent 3.5.2 · notarized ZIP + DMG · automated test suite
- [x] Public release [v3.5.2](https://cfgauss.com.br/t/notchagent-releases)
- [x] Homebrew Cask install
- [x] Packaged `.app` with icon + launch-at-login + notifications
- [x] Developer ID signature + notarization + stapled ticket
- [x] Notarized DMG + signed ZIP with published SHA-256 digests
- [x] Auto-update (Sparkle 2) — HTTPS appcast, embedded EdDSA public key, and release signature verified
- [ ] Stable-channel promotion — waits for the physical soak and pilot gates

Commercial release builds use `NOTCHAGENT_UPDATE_FEED_URL` and
`NOTCHAGENT_UPDATE_PUBLIC_ED_KEY`. After notarization,
`Scripts/generate-update-appcast.sh` creates the signed appcast locally; it does
not upload or publish files. Keep Sparkle's private EdDSA key in the macOS
Keychain.
- [x] Product site on [notchagent.app](https://notchagent.app)
- [x] Free and open source — no licensing planned

## Observability

```bash
/usr/bin/log stream --predicate 'subsystem == "br.com.lfrprojects.notchagent"' --level debug
```

---

<p align="center">
  <strong>NotchAgent is a flagship project from <a href="https://github.com/luisroquette/RocketLabs">RocketLabs</a>.</strong><br />
  <sub>Applied AI systems built in public.</sub>
</p>
