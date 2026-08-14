# NotchAgent Desk

NotchAgent Desk extends NotchAgent to a 480x320 ESP32-S3 touch display. It is a
physical interface, not a second collector: providers, credentials, polling,
history, projections, and alert decisions remain on the Mac.

## Data flow

`Providers -> RefreshScheduler -> UsageStore -> DeskSnapshotFactory -> USB CDC -> ESP32 -> LVGL`

The bridge observes consolidated store changes and never starts provider
requests. The device cannot request a refresh or modify settings.
Discovery, firmware/protocol identity, and local hardware telemetry start
automatically. Mirroring sanitized usage snapshots is disabled by default and
controlled independently in NotchAgent Settings.
Bundled recovery firmware is accepted only from an intact app signed by the
NotchAgent Apple development team; the bundle identifier alone is insufficient.

The final app 3.1.0 build 3 was physically validated in discovery-only mode on
firmware 0.6.6: protocol 1.1 and healthy hardware telemetry were received while
the report contained no provider, account, billing, credential, token, or
serial-path fields.

## Wire contract v1

- 4-byte magic `NADK`, protocol major, frame type, sequence, payload length.
- UTF-8 JSON payload inside a COBS frame, terminated by zero and protected by CRC32.
- Maximum payload: 16 KiB. Major mismatches, malformed lengths, unknown types,
  invalid JSON, and bad checksums are rejected.
- Frame types: hello, hello acknowledgement, snapshot, heartbeat, device telemetry.

Snapshots expose provider IDs, bounded metrics and aggregate service state.
They exclude account UUIDs and labels, notes, raw errors, billing scopes,
credentials, identifiers, and monetary amounts.

## Release gates

The software build can run without hardware. Physical release still requires
display/color/touch validation and the Beta 1 reliability gates below. Device
telemetry exposes FPS, heap, reset reason, frame errors, handshake count, touch
count, and touch latency locally over USB.

## Beta 1 reliability gates

Reliability scripts discover a single `/dev/cu.usbmodem*` automatically. If
more than one USB modem is attached, set `NOTCHAGENT_DESK_PORT` explicitly;
the scripts fail closed instead of guessing a device.

- `Scripts/notchagent-desk-reconnect.sh 100`: 100 physical ESP32 reset, USB
  reconnect, authenticated handshake, and healthy-telemetry cycles. It persists
  every cycle; `notchagent-desk-reconnect-evidence.sh` rejects partial runs and
  creates the aggregate, SHA-256-linked evidence.
- `Scripts/notchagent-desk-soak.sh 86400`: launches the real signed app with
  network refresh disabled, then assesses 24 hours of bridge connection and
  incremental device telemetry. Its evidence retains the raw JSONL and the Beta
  gate recalculates every metric, UTC duration, and sample gap. Scheduling gaps
  above 16 seconds, sleep, or clock rollback fail the run.
  `Scripts/notchagent-desk-telemetry-soak.sh` remains
  available for firmware-only isolation.
- `Scripts/notchagent-desk-power-cycle.sh`: requires a real cable disconnect,
  observes USB disappearance/re-enumeration, then requires healthy telemetry
  with a cold-boot `power_on` reset reason.
- `Scripts/notchagent-desk-matrix-gate.sh /path/to/private-matrix.json`: validates
  10 healthy attempts on direct USB, dock, and hub across at least two
  non-identifying Mac classes. Start from
  `docs/NOTCHAGENT_DESK_MATRIX_TEMPLATE.json`.
- After each `Scripts/notchagent-desk-reconnect.sh 10` run, use
  `Scripts/notchagent-desk-matrix-entry.sh` to convert its raw report into one
  sanitized matrix entry without manual metric transcription. Every matrix
  entry retains its raw reconnect report and is bound to the exact firmware
  image/build-input fingerprint and a unique report SHA. The gate recalculates
  every metric from that report, so the same run cannot represent two ports.
- `Scripts/notchagent-desk-touch.sh 45`: requires a real touch during the test
  window and enforces the latency gate.
- During an app-integrated soak, `Scripts/notchagent-desk-touch-observe.sh 45`
  observes the live sanitized report instead of competing for the USB port;
  it requires both a real touch and 10 seconds of stable release state.
- Minimum free heap: 120 KiB (122,880 bytes); minimum rendered FPS: 7
  (measured baseline: ~7.46 on the current QSPI panel).
- Maximum measured touch latency: 100 ms after at least one touch.
- Zero invalid frames and no panic, watchdog, or brownout reset.

The scripts never transmit a hardware identifier, provider data, or telemetry
to a remote service. Reports stay under the local temporary directory.
Release contracts, gate evidence, and their raw sources must be regular files;
symbolic links are rejected before validation.

## Current certification evidence

Run `Scripts/notchagent-desk-beta1-status.sh` for a machine-readable operational
view that separates the active soak, required physical actions, and external
commercial/signing gates without weakening the final release gate.

- HISTORICAL: 100/100 physical reset and USB reconnect cycles on firmware 0.6.3,
  completed 2026-08-13 in 826.107 seconds. Maximum reconnect was 10.305s
  (5.023s reset + 5.289s telemetry), with zero I2C or frame errors. Evidence:
  `docs/evidence/notchagent-desk-beta1-reconnect-0.6.3-2026-08-13.json`.
- HISTORICAL: final app 3.1.0 build 3 physically auto-discovered firmware 0.6.6 and
  maintained healthy telemetry during a 96-second smoke test. Evidence:
  `docs/evidence/notchagent-desk-beta1-final-smoke-20260813T201221Z.json`.
- HISTORICAL: 100/100 physical reset and USB reconnect cycles on firmware
  0.6.2 completed 2026-08-13 in 807.948 seconds. Aggregate evidence is stored
  in `docs/evidence/notchagent-desk-beta1-reconnect-0.6.2-2026-08-13.json`.
  It does not satisfy the current 0.6.16 release gate.
- INVALIDATED: physical touch evidence on firmware 0.6.2 counted stale
  coordinates as new polling touches after release. The historical report is retained at
  `docs/evidence/notchagent-desk-beta1-touch-0.6.2-2026-08-13.json`.
- INVALIDATED: firmware 0.6.5 developed a phantom IRQ/touch storm after 4,933
  seconds. The failed raw soak remains preserved locally for diagnosis.
- FIXED AND PHYSICALLY IDLE-VALIDATED: firmware 0.6.6 reads coordinates only
  after an IRQ using the known-good eight-byte AXS15231B command. Passive health
  probes no longer create touches, and the Mac rejects IRQ storms.
- INVALIDATED: interactive validation on firmware 0.6.6 passed touch, swipe,
  runner jump, release, and latency, but exposed a transient 5.80 FPS sample.
- INVALIDATED: firmware 0.6.7 fixed the FPS window, but one physical test
  produced IRQs without coordinates because its dedicated task could read the
  controller before touch data settled.
- HISTORICAL: firmware 0.6.8 retained the two-second FPS window and waited at least
  2 ms after an IRQ before the coordinate command.
- PENDING: final signed local recovery on app 3.1.1 build 4 with Developer ID;
  the earlier development-signed flash completed, but did not persist release-grade evidence.
- PASS: firmware 0.6.8 physically passed tap, swipe-left, swipe-right, runner
  jump, stable release, and latency at 5.483 ms. Evidence:
  `docs/evidence/notchagent-desk-beta1-touch-0.6.8-2026-08-13.json`.
- INVALIDATED: the 0.6.8 soak later treated isolated static redraws as a 1.99
  FPS animation, even though touch and active rendering remained responsive.
- INVALIDATED: firmware 0.6.9 introduced the BURN forecast and active-animation
  FPS sampling, but its labels still required the user to interpret internal
  terms such as pace and reset-first.
- INVALIDATED: firmware 0.6.10 made BURN answer `WILL I RUN OUT BEFORE RESET?`
  directly with `YES / SLOW DOWN`, `NO / YOU'RE SAFE`, or a learning state.
  Physical review exposed an empty half-screen chart and an unsafe `YOU'RE SAFE`
  claim when the provider did not report a reset time.
- HISTORICAL: firmware 0.6.11 uses the full width for remaining runway, window,
  reset, pace, forecast, and action. Missing reset data now produces an explicit
  `RESET TIME UNKNOWN` state instead of a false safety conclusion.
- PASS: firmware 0.6.12 physically reported its own version after the focused
  BURN UI/UX pass. It adds a compact
  forecast header, bordered decision instrument, semantic color separation,
  full-width runway, and modular window/reset/pace readouts.
- HISTORICAL: firmware 0.6.13 redesigns MODELS around model contribution and
  health: ranked rows, proportional token bars, total usage, probe state, and
  latency. Physical update tests now fail before flashing a stale app bundle.
- HISTORICAL: firmware 0.6.14 redesigns RHYTHM as a weekly work-pattern
  instrument: peak hour, weekly token volume, strongest day period, and a
  compact hourly flow chart with explicit scope and semantic peak highlight.
- WITHDRAWN: firmware 0.6.15 redesigned API as an operational triage panel,
  but API-account setup is intentionally outside the Desk Beta scope.
- CANDIDATE: firmware 0.6.16 removes the API page, its navigation target,
  ambient recommendation, API-account provider fallback, and `apiServices`
  payload. The Beta now has four self-configuring pages: NOW, BURN, RHYTHM,
  and MODELS.
- PENDING: start the supervised 0.6.16 soak after physical layout validation.
- PENDING: 100 reconnects and the replacement soak on 0.6.16,
  abrupt-power recovery, and the
  dock/hub/Mac matrix. These gates must not be inferred from the passing
  historical firmware tests.

`Scripts/notchagent-desk-beta1-gate.sh` reads the machine-readable status in
`docs/evidence/notchagent-desk-beta1-status.json` and fails closed while any
release or commercial gate lacks evidence.

Run `Scripts/check-notchagent-desk.sh` before committing. CI repeats the
privacy/protocol tests, firmware build, public-release audit, and diff check
with pinned Arduino dependencies.
