# NotchAgent for Windows

The Windows companion to [NotchAgent](../README.md) — a system-tray widget that
answers the same question the Mac app does: **how much of my Claude Code /
Codex limit is left, right now?**

There is no "notch" on Windows, so the closest honest equivalent is a system
tray icon (color-coded by state) that opens a small popover with the same
provider cards, official Anthropic quota probe, and the Clawd dino-game
mascot — built with .NET 8 + [Avalonia UI](https://avaloniaui.net) (not
Electron/WebView).

## Status: v1 (initial port)

Ported from the Mac app's calibrated logic (same JSONL parsers, same
"current window" semantics, same threshold-alert/recovery lifecycle):

- Tray icon (green/yellow/red by aggregate state) + popover with Claude and
  Codex cards: % left, tokens, cost estimate, reset countdown.
- Official Claude quota probe (same technique as the Mac app: a 1-token
  request to `api.anthropic.com`, reading the `anthropic-ratelimit-unified-*`
  headers). Token located via `CLAUDE_CODE_OAUTH_TOKEN` env var or
  `%USERPROFILE%\.claude\.credentials.json`.
- Codex: rollout parsing with plan-aware window classification and the
  "current session" fallback for weekly-only plans.
- Threshold alerts (25/15/10/5% left) and the blocked→restored recovery
  banner.
- Clawd dino-game runner, wired to the real session gauge.
- Dark/Light/Auto theme, refresh interval, alert thresholds — Settings window.

**Not yet ported** (Mac-only for now): burn chart, hourly rhythm chart, the
per-model probe page, system notifications (toast), launch-at-login.

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
- Built and validated on macOS (no Windows machine available in this
  environment) — the parsers were verified against this machine's *real*
  Claude/Codex data and match the Mac app's numbers exactly, and the UI was
  visually validated by running the same Avalonia app locally on macOS
  (Avalonia is cross-platform). The actual Windows executable itself has
  not been run on a physical Windows machine yet — please report any
  Windows-specific issues (tray icon behavior, DPI scaling, etc).
- `%APPDATA%\NotchAgent` for settings/snapshots — no collision with the Mac
  app in real use (different machines); this only matters if you build both
  on the same dev box.
