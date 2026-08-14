# NotchAgent Desk Beta 1 onboarding

1. Install the signed NotchAgent release on a Mac running macOS 14 or later.
2. Connect NotchAgent Desk with any compatible USB **data** cable. A charge-only
   cable powers the screen but cannot connect the app.
3. NotchAgent opens **Settings → Desk** automatically on the first connection.
   It shows the exact Codex state: not installed, authentication required,
   first session required, or ready. Authentication opens the official Codex
   sign-in flow; credentials remain owned by Codex and are never read by NotchAgent.
4. If requested, click **Create first session**. NotchAgent opens Codex in
   Terminal and refreshes local data automatically after the first session starts.
5. Confirm **Display**, **Claude Code** or **Codex**, then click **Enable my Desk**.
   This is the only consent step and sends sanitized local usage to the display.
6. When the header says **Your Desk is ready**, setup is complete. Firmware, protocol,
   health, update, and safe export remain under **Diagnostics and recovery**.

Portuguese guide: [NOTCHAGENT_DESK_ONBOARDING.pt-BR.md](NOTCHAGENT_DESK_ONBOARDING.pt-BR.md)

## Verify the Desk

- Swipe left and right: each gesture must move exactly one page.
- Tap the Claude mascot in the runner: it must jump immediately.
- Settings must show the same firmware version in identity and telemetry, a
  present touch controller, zero read errors, and touch latency below 100 ms.

## Recovery without Terminal

- If the display shows a PIN or Wi-Fi setup, it is running the legacy firmware.
  No PIN is needed for NotchAgent Desk. Keep it connected, open Settings while
  the status says **Recognizing** or **Firmware incompatible**, and click
  **Update firmware**.
- Do not press unidentified board buttons during a normal update. The signed
  updater enters flash mode and resets the Desk automatically.
- If the screen powers on but the Mac never shows **Recognizing**, replace the
  cable first: this almost always means a charge-only cable or a non-data dock
  port. Disconnect other USB modem boards while recovering.
- If the update fails, reconnect the same cable once and retry. Export **Safe
  diagnostic** before contacting support if the port is detected.

The device has no Wi-Fi, cloud account, provider credentials, or independent
API polling. The optional Anthropic quota probe is off by default and requires
separate explicit consent. Export **Safe diagnostic** when support needs device-health data;
the report excludes serial paths, account identifiers, credentials, amounts,
and raw errors.

Canonical onboarding and download entry point:
<https://github.com/luisroquette/notchagent/blob/master/docs/NOTCHAGENT_DESK_ONBOARDING.md>

Do not print the production onboarding card until this exact URL is published
and `NotchAgent-Desk-Beta1-3.1.1.zip` is available from the `v3.1.1` repository
release with the same SHA-256 recorded by the notarization gate.
