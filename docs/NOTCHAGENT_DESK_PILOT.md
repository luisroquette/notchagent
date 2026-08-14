# NotchAgent Desk Beta 1 pilot

## Cohort

Five participants for seven consecutive days, covering direct USB and at least
two different docks/hubs. Participation and any diagnostic sharing require
explicit consent. All participants use the same seven calendar dates.
Use `docs/NOTCHAGENT_DESK_CONSENT_EVIDENCE_TEMPLATE.json` for each participant.
The record and signed/private PDF or image stay outside the repository; only
their private paths and hashes enter the private pilot file.
Prefer `Scripts/notchagent-desk-consent-evidence.sh`; it calculates the document
hash, validates PDF/PNG/JPEG/HEIC, and refuses overwrite or symlinks.

## Acceptance gates

- All five complete onboarding without terminal commands.
- At least 95% of observed sessions connect automatically within 10 seconds.
- No unrecoverable firmware update and no credential or financial-data exposure.
- Per successful daily session: zero panic/watchdog/brownout resets, minimum
  heap >=120 KiB, FPS >=7, at least one physical touch, and maximum touch
  latency <=100 ms.
- Every accepted session runs the Beta 1 firmware version 0.6.16.
- Every successful day retains its sanitized JSONL source; the gate recalculates
  the daily summary and rejects missing, linked, reused, changed, or inconsistent reports.
- Touch, swipe, runner, alerts, and recovery are rated usable by at least four participants.
- Every participant rating recovery usable must have one daily firmware update
  recorded as passed.

## Daily capture

Record only aliases, date, connection timing, dock class, firmware version,
health measurements, update result, and the bounded usability flags in the
template. Do not record free-form personal data, provider credentials, account
IDs, serial paths, prompts, token contents, or financial amounts.
The validator rejects every field outside this closed schema. If a connection
fails, record the four unavailable health measurements as `null` and set
`healthPass` to `false`.

Create a complete private 5 × 7 scaffold with
`Scripts/notchagent-desk-pilot-init.sh /absolute/private-pilot.json YYYY-MM-DD`.
For each successful daily session, use `Scripts/notchagent-desk-pilot-day.sh`
to derive its bounded metrics from the sanitized app report and insert that
closed JSON object into the participant day. Keep the completed file private
and validate it with `Scripts/notchagent-desk-pilot-gate.sh`. The gate
requires five unique participant and unit aliases, seven consecutive days each,
at least 34 of 35 successful connections within 10 seconds, two dock/hub
  aliases, five unique consent documents, zero severity-1 defects, and the usability targets.
It validates the numeric reset, heap, FPS, and touch-latency evidence instead of
trusting a standalone health flag. It also requires at least two non-identifying
Mac classes; do not record a Mac serial number, hostname, account name, email,
or hardware UUID.
Each successful day carries the SHA-256 of its sanitized source report, and the
gate rejects report reuse across participants or days.
Daily derivation rejects intermediate disconnects, sample gaps above 10
seconds, missing touch controllers, and any recorded reliability failure.

## Exit decision

Ship only if every safety gate passes and no severity-1 defect remains. A failed
hardware gate returns the unit to firmware/QC; a failed onboarding gate returns
the app and documentation to the product loop.
