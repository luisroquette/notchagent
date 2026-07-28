# NotchAgent

<p align="center">
  <strong>Know when your AI agents will hit a limit, what your APIs have cost, and how much balance remains.</strong>
</p>

<p align="center">
  <a href="https://github.com/luisroquette/RocketLabs"><img src="https://img.shields.io/badge/RocketLabs-flagship%20project-7C5CFC?style=flat-square" alt="RocketLabs flagship project" /></a>
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/version-v2.0.0-38D6C7?style=flat-square" alt="Version v2.0.0" /></a>
  <a href="https://github.com/luisroquette/notchagent/actions/workflows/public-release-security.yml"><img src="https://img.shields.io/github/actions/workflow/status/luisroquette/notchagent/public-release-security.yml?branch=master&style=flat-square&label=security%20%2B%20tests" alt="Security and tests" /></a>
  <a href="#install"><img src="https://img.shields.io/badge/install-Homebrew-F3B85A?style=flat-square" alt="Install with Homebrew" /></a>
</p>

<p align="center">
  <a href="#install"><strong>Install NotchAgent</strong></a>
  &nbsp;·&nbsp;
  <a href="#api-cost-monitoring">See what 2.0 monitors</a>
  &nbsp;·&nbsp;
  <a href="docs/API_ACCOUNT_MONITORING.md">Read the data model</a>
</p>

**Current version: 2.0.0** · Source release dated July 28, 2026 · [Changelog](CHANGELOG.md)

NotchAgent is a native macOS control panel for Claude Code, Codex, API accounts,
and AI subscriptions. It lives in the MacBook notch, stays out of the way, and
shows the numbers that decide whether work can continue: quota left, reset time,
burn rate, recent spend, current balance, and recurring plan cost.

There is no hosted dashboard or product telemetry, and credentials are never
sent to a NotchAgent server.

![NotchAgent compact bar showing Claude and Codex capacity](docs/img/notch-compact.png)

![NotchAgent expanded above the desktop](docs/img/desktop-now.png)

## Stop finding out after the workflow stops

An agent can fail for painfully ordinary reasons: a weekly limit expires, an API
balance reaches zero, or a plan renews at a price nobody remembered. Those
numbers usually live across several provider portals and incompatible billing
screens.

NotchAgent keeps the operational answer visible:

| You need to know | NotchAgent shows |
|---|---|
| Can the agent finish this session? | Official quota left, reset time, and burn projection |
| What did the API cost recently? | Provider-reported spend with its exact time window |
| How much can still be used? | Current prepaid balance or native service quota |
| What will renew? | Monthly plan cost, renewal date, and budget forecast |
| Can this number be trusted? | Source, freshness, and whether it is official or derived |

## What you see in three seconds

- **NOW:** quota remaining, reset countdown, account health, and the limiting window.
- **BURN:** whether the current pace reaches the reset or runs out first.
- **API COSTS:** spend, balance, and plan price kept as separate financial fields.
- **ALERTS:** escalating warnings at 25%, 15%, 10%, and 5% remaining.
- **HISTORY:** daily usage, hourly rhythm, provider breakdown, and sanitized events.

| NOW: capacity and reset | BURN: pace and projection |
|---|---|
| ![NOW page](docs/img/panel-now.png) | ![BURN page](docs/img/panel-burn.png) |

| RHYTHM: usage by hour | MODELS: availability and local cost estimate |
|---|---|
| ![RHYTHM page](docs/img/panel-rhythm.png) | ![MODELS page](docs/img/panel-models.png) |

![Escalating low-fuel alert](docs/img/alert-almost-empty.png)

<details>
<summary><strong>More product screenshots</strong></summary>

![Burn chart scrubbing](docs/img/desktop-burn.png)
![Dashboard usage history](docs/img/dashboard-1.png)
![Dashboard provider breakdown](docs/img/dashboard-2.png)
![NotchAgent settings](docs/img/settings.png)

</details>

## API cost monitoring

Version 2.0 adds a financial layer for AI infrastructure. Each account gets the
same three-column answer whenever the provider exposes it:

> **Spent, last 30 days** · **Balance now** · **Plan per month**

For example, an illustrative card can show `R$ 24.00 spent`, `R$ 76.00
available`, and `R$ 100.00/month`. These are independent values. A top-up never
becomes spend, and missing data stays missing instead of being presented as zero.

### Supported accounts

| Provider | What NotchAgent can read |
|---|---|
| Anthropic API | Console spend, credits, and the period exposed by the account |
| OpenAI API | Usage costs and prepaid balance |
| DeepSeek | 30-day spend and current balance |
| OpenRouter | 30-day spend and current balance |
| Google AI Studio / Gemini | Official BRL spend for Google's 28-day window |
| xAI / Grok | Spend and balance when exposed by the account |
| ElevenLabs | Used quota, remaining quota, reset, and plan |
| Firecrawl | Credits used, credits remaining, overage, reset, and plan |
| twitterapi.io | Credits, usage, and balance equivalent when the plan is known |
| X / Twitter | Consumption, top-ups, and balance for each connected project |
| Custom read-only endpoint | Declared quota fields from your own HTTPS endpoint |

Add as many accounts as needed, including multiple accounts from the same
provider. Cards can be reordered, refreshed individually, and disconnected
without touching the other accounts.

Web subscriptions such as Claude, Claude Code, and ChatGPT appear in a separate
section. Subscription charges are never mixed with API consumption.

## Numbers with provenance

Financial dashboards become dangerous when they make different kinds of data
look equally certain. NotchAgent records the origin of every monetary field:

- **Official API:** returned by a documented provider endpoint.
- **Official portal:** read from the provider account you explicitly connected.
- **Manual:** entered by you when no machine-readable source exists.
- **Derived estimate:** proportional value calculated from a confirmed plan and quota.

The default comparison window is 30 rolling days. Google AI Studio keeps its
official 28-day window, clearly labeled. USD values are converted with the
current Banco Central do Brasil PTAX rate, never a hardcoded exchange rate.

If a provider does not expose spend or balance, the card shows the field as
unavailable. NotchAgent does not manufacture an "official" number.

## Privacy by design

- API credentials are stored in the macOS Keychain.
- Connected portals use one isolated WebKit profile per account.
- Account monitoring is opt-in and talks directly to the selected provider.
- Exported diagnostics remove credentials, cookies, identities, labels, and amounts.
- There is no NotchAgent backend and no product telemetry.

The optional Anthropic quota probe is the only feature that can send a paid
one-token model request. It can be disabled in Settings. External API account
monitoring is read-only and does not call paid generation models.

## Install

### Homebrew

The Homebrew cask installs the latest published stable release:

```bash
brew install --cask luisroquette/tap/notchagent
xattr -dr com.apple.quarantine /Applications/NotchAgent.app
open /Applications/NotchAgent.app
```

### Download

Download the latest package available on
[GitHub Releases](https://github.com/luisroquette/notchagent/releases/latest),
move NotchAgent to `/Applications`, then run:

```bash
xattr -dr com.apple.quarantine /Applications/NotchAgent.app
open /Applications/NotchAgent.app
```

### Build version 2.0 from source

Requires macOS, Xcode 15+, and a Swift 6 toolchain:

```bash
git clone https://github.com/luisroquette/notchagent.git
cd notchagent
./Scripts/audit-public-release.sh
git config core.hooksPath .githooks
./Scripts/make-app.sh
open dist/NotchAgent.app
```

NotchAgent uses the first local Apple Development identity when available.
Set `NOTCHAGENT_SIGN_IDENTITY` to choose another stable signing identity. It
falls back to ad-hoc signing when no identity is available.

## Connect your first account

1. Open **Settings → API Accounts**.
2. Click **+** and choose a provider.
3. Store a read-only credential in Keychain or select **Connect account**.
4. Confirm the source, time window, and freshness shown on the card.

The public repository ships with no configured accounts, names, projects,
credentials, cookies, or personal financial history.

## Who it is for

- Developers running Claude Code, Codex, or several model providers every day.
- Small teams that cannot afford a silent API balance failure.
- AI operators managing multiple client, project, or social accounts.
- Anyone paying for overlapping AI plans and trying to understand the real monthly total.

NotchAgent also works on Macs without a physical notch using a floating compact
pill. A Windows system-tray companion is available in
[`windows/README.md`](windows/README.md) with the current Windows feature set.

## Frequently asked questions

<details>
<summary><strong>Is NotchAgent an official client from Anthropic, OpenAI, or another provider?</strong></summary>

No. NotchAgent is an independent RocketLabs product. Provider names and logos
identify compatible services and do not imply endorsement.

</details>

<details>
<summary><strong>Why can one provider show spend but not balance?</strong></summary>

Providers expose different billing fields. NotchAgent displays only what the
connected source can verify and marks unavailable fields explicitly.

</details>

<details>
<summary><strong>Does monitoring consume model tokens?</strong></summary>

API account monitoring uses read-only billing, quota, and portal sources. The
optional Anthropic quota probe sends a one-token request at its configured
cadence and can be disabled.

</details>

<details>
<summary><strong>Does it work without a MacBook notch?</strong></summary>

Yes. The compact monitor becomes a floating pill on displays without a notch.

</details>

## For contributors

<details>
<summary><strong>Architecture, precision model, and local verification</strong></summary>

```text
Providers → UsageSnapshot → UsageStore → Notch · Menu Bar · Dashboard
     ↑ parsers/actors       ↑ alerts, burn rate, status aggregation
RefreshScheduler ──────────→ SnapshotStore / HistoryStore
```

Local sources include Claude transcripts under `~/.claude/projects`, Codex
rollouts under `~/.codex/sessions`, and Gemini CLI logs. Official quota
percentages and reset times remain separate from locally counted tokens and
public-price cost estimates.

Run the complete public validation:

```bash
./Scripts/check-version.sh
./Scripts/audit-public-release.sh
NOTCHAGENT_DISABLE_PAID_PROBES=1 swift test
```

The suite currently contains 200 tests. Live account E2E is read-only and
opt-in:

```bash
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
NOTCHAGENT_LIVE_E2E=1 \
swift test --filter testLiveE2EAccountMonitoringWhenExplicitlyEnabled
```

See [API account monitoring](docs/API_ACCOUNT_MONITORING.md) for field
semantics, refresh behavior, source tolerances, and the custom endpoint
contract.

</details>

## Known limitations

- Public packages are not notarized yet, so first launch requires clearing quarantine.
- Provider portals can change without notice and may require reconnecting the account.
- Some providers expose quota but no monetary balance; unavailable fields remain blank.
- Local token counts cannot include web conversations that leave no local transcript.

## Versioning

NotchAgent follows [Semantic Versioning](https://semver.org/). `VERSION` is the
source of truth. The app bundle, README, and top entry in `CHANGELOG.md` must
match before a release can pass CI.

---

<p align="center">
  <strong>Built by <a href="https://github.com/luisroquette/RocketLabs">RocketLabs</a>.</strong><br />
  <sub>Operational clarity for people who depend on AI every day.</sub>
</p>
