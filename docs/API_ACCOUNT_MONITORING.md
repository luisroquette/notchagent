# API financial monitoring

NotchAgent only monitors accounts enabled under **Settings → API Accounts**.
Credentials live in the macOS Keychain. Preferences, snapshots, diagnostics
and logs never store keys, tokens, cookies, account IDs, or secret values.

## Financial model

Each card keeps independent fields. A missing field stays missing:

- **Window spend**: consumption billed in the official period shown on the card.
- **Current balance**: credit available right now; top-ups are never
  classified as spend.
- **Monthly plan**: recurring price confirmed by the provider or the portal.
- **Top-up**: purchased credit, kept separate from consumption.
- **Quota**: the service's native unit. A conversion to reais only ever
  appears as a **proportional estimate**, never as an official value.

The default window is **30 rolling days**. Google AI Studio is the explicit
exception: its official portal provides **28 days**, preserved on the card.
NotchAgent never sums different periods into a single total.

Official values already published in reais, like Google AI Studio's, stay in
BRL. Official values in USD use the current USD/BRL rate, with its source and
timestamp recorded; the rate is never hardcoded.

## Accounts and sources

| Account | Preferred official source | Result |
| --- | --- | --- |
| Anthropic API | Connected Anthropic Console | Spend, balance/credits and window available from the portal |
| OpenAI API | Connected Usage/Costs + Billing | 30-day spend and current balance |
| DeepSeek | Balance API + connected portal | 30-day spend and current balance |
| OpenRouter | Credits API + connected portal | 30-day spend and current balance |
| Google / Gemini | Connected Google AI Studio | Official BRL spend over 28 days; balance only if the provider reports it |
| xAI / Grok | Management API/portal | Spend and balance when exposed by the account |
| ElevenLabs | Subscription API | Quota, usage, reset and plan |
| Firecrawl | Credits API | Quota, usage, reset and plan; a negative balance becomes zero + overage |
| twitterapi.io | Credits API | Quota, usage, and equivalent balance when the plan is known |
| X / Twitter (each account) | Connected X Console | Consumption, top-ups and balance, never mixing projects |
| Custom endpoint | Read-only HTTPS | Only the fields declared by the contract |

Personal subscriptions, like Claude/Claude Code and ChatGPT, live under
**Connected subscriptions** and don't count as API consumption.

## Integrity and refresh

Each value keeps its origin: **official API**, **official portal**, **manual
entry**, or **derived estimate**. When both the API and the portal report the
same field, NotchAgent compares the sources with a tolerance of 0.02 USD,
0.10 BRL, or one quota unit. Discrepancies leave the card partial and show up
in the detail view.

Periodic refresh uses a 15-minute cache. **Global refresh**, an individual
card refresh, completing a login, and disconnecting all invalidate the cache
before the next read. Refresh generations keep a stale response from
overwriting newer data.

Visible states per card:

- **Refreshing**
- **Updated**
- **Stale**
- **Error**, with a sanitized cause

## Security and diagnostics

Portal connections use a WebKit profile isolated per account. Disconnecting
only removes that profile's session. The exportable diagnostic contains
states, sources and windows, but strips credentials, cookies, identifiers,
labels, free-text messages and financial amounts.

Integrity E2E tests are read-only. Use:

```bash
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
NOTCHAGENT_LIVE_E2E=1 \
swift test --filter testLiveE2EAccountMonitoringWhenExplicitlyEnabled
```

This run never calls paid Anthropic, OpenAI, Gemini or OpenRouter models.

## Custom endpoint

The HTTPS endpoint must accept `Authorization: Bearer` and return:

```json
{
  "used_percent": 42,
  "resets_at": "2026-08-01T00:00:00Z",
  "note": "optional"
}
```

`remaining_percent` can replace `used_percent`. Unknown fields are ignored.
