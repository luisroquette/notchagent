# NotchAgent for Windows

The Windows companion to [NotchAgent](../README.md) — answers the same
question the Mac app does: **how much of my Claude Code / Codex limit is
left, right now?**

There is no "notch" on Windows, so the closest honest equivalent is **a
small, always-on-top bar docked to the very top of the screen** — the same
glance-and-go feel, minus the physical camera housing. It sits compact by
default, expands on hover (debounced, just like the Mac notch), pins open on
click, and gets out of the way of fullscreen apps (games, video, presentations)
the way Discord/NVIDIA overlays do. The system tray icon is secondary: it
reflects the aggregate state by color and offers a right-click menu (Refresh,
Pause, Settings, Show Bar, Quit) as a fallback if the bar is ever dismissed.
Built with .NET 8 + [Avalonia UI](https://avaloniaui.net) — not Electron/WebView.

## Status: v1

Ported from the Mac app's calibrated logic (same JSONL parsers, same
"current window" semantics, same threshold-alert/recovery lifecycle):

- Floating top bar: compact strip (Claude + Codex readouts, mini meters, the
  Clawd dino-game runner) that expands to full provider cards on hover.
- Official Claude quota probe (same technique as the Mac app: a 1-token
  request to `api.anthropic.com`, reading the `anthropic-ratelimit-unified-*`
  headers). Token located via `CLAUDE_CODE_OAUTH_TOKEN` env var or
  `%USERPROFILE%\.claude\.credentials.json` (Windows Credential Manager
  integration, the Keychain equivalent, is not yet ported — see limitations).
- Codex: rollout parsing with plan-aware window classification and the
  "current session" fallback for weekly-only plans.
- Threshold alerts (25/15/10/5% left) and the blocked→restored recovery
  banner.
- Auto-hide when a fullscreen window has focus on the bar's monitor.
- Dark/Light/Auto theme, refresh interval, alert thresholds — Settings window.

**Not yet ported** (Mac-only for now): burn chart, hourly rhythm chart, the
per-model probe page, system toast notifications, launch-at-login.

## Build

Requires the .NET 8 SDK (works from macOS, Linux or Windows — Avalonia has
no Windows-only build dependencies):

```bash
cd NotchAgent.Windows
dotnet run                      # run locally (works on macOS/Linux too, for dev)
dotnet build                    # quick compile check

# Produce a real standalone Windows .exe (no .NET install required on the
# target machine) — this works even when building FROM macOS/Linux:
dotnet publish -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -o ../publish-win-x64
```

The result is a single `NotchAgent.Windows.exe` (~90 MB, self-contained).

## Known limitations

- Not code-signed. Windows SmartScreen will warn on first run ("Windows
  protected your PC") — click "More info" → "Run anyway". Signing requires
  an Authenticode certificate, a separate step from this build.
- Built and validated end-to-end on macOS (no Windows machine available in
  this environment): the same Avalonia app runs locally on macOS (Avalonia
  is cross-platform for dev), which is how a real cross-thread crash in the
  refresh scheduler and a null-payload parsing edge case in the Codex parser
  were caught and fixed against this machine's *real* Claude/Codex data —
  both providers now refresh cleanly with live numbers. The Windows `.exe`
  itself has not been run on a physical Windows machine yet — please report
  any Windows-specific issues (tray icon behavior, DPI scaling, monitor
  detection, etc).
- Windows Credential Manager (the Keychain equivalent) isn't wired up yet —
  the quota probe only checks the env var and the plain credentials JSON
  file, so it silently falls back to local token-count budgets if neither
  is present.
- `%APPDATA%\NotchAgent` for settings/snapshots on real Windows. When
  developing/testing this cross-platform app *on macOS*, it deliberately
  uses `NotchAgent-Windows-Dev` instead of `NotchAgent` under
  `~/Library/Application Support` — otherwise a local test run would
  overwrite the native Mac app's real snapshot file on a shared dev machine
  (harmless on separate machines, so real Windows users are unaffected).
