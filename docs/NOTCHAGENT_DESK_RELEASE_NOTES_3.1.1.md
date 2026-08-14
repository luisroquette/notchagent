# NotchAgent 3.1.1 — Desk Beta 1

NotchAgent Desk Beta 1 turns the macOS app and the companion ESP32-S3 display
into a local, plug-and-play Codex status surface.

## Highlights

- Detects the Desk automatically over USB and verifies firmware protocol 1.1.
- Guides Codex installation, official sign-in, and first-session setup in PT/EN.
- Mirrors sanitized local usage data only after explicit consent.
- Includes firmware 0.6.16 and signed in-app recovery without Terminal commands.
- Adds automatic app updates, diagnostics, factory QC, and release evidence gates.

## Installation

1. Download `NotchAgent-Desk-Beta1-3.1.1.zip` from this release.
2. Move NotchAgent to Applications and open it.
3. Connect the pre-flashed Desk using the included USB data cable.
4. Follow **Settings → Desk** until the app shows **Your Desk is ready**.

Requires macOS 14 or later. The application is Developer ID signed, notarized,
stapled, and distributed with Hardened Runtime enabled.

## Beta scope

The release passed the signed recovery flow and 100 physical USB reset/reconnect
cycles. The 24-hour duration, physical touch-latency, abrupt-power, and dock/hub
matrix gates were explicitly accepted as Beta risks and remain documented as
waivers rather than successful tests.
