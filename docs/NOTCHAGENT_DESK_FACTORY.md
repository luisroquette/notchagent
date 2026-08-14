# NotchAgent Desk Beta 1 factory station

## Station

- macOS 14+ with the pinned Arduino toolchain and one known-good USB data cable.
- One Desk connected at a time; no other `/dev/cu.usbmodem*` device attached.
- Current verified factory package under `firmware/notchagent_desk/release`.
- Non-identifying unit aliases in the sequence `DESK-B1-NNN`.

## Per-unit flow

1. Inspect the board, connector, enclosure, ventilation, and touch surface.
2. Create private evidence from `docs/NOTCHAGENT_DESK_FACTORY_VISUAL_TEMPLATE.json`
   with four distinct PNG/JPEG/HEIC artifacts showing display, touch response,
   completed swipe, and the runner airborne. Prefer
   `Scripts/notchagent-desk-factory-visual-evidence.sh`; it calculates every hash,
   refuses overwrite/symlinks, and validates the record before saving it.
3. Run `Scripts/notchagent-desk-factory-qc.sh` with the explicit port, unit alias,
   approved lot, `NOTCHAGENT_DESK_QC_VISUAL_EVIDENCE`, and all four checks.

For pre-production layout review only, the product owner may explicitly replace
private unit photos with a live signed-macOS AI review validated by
`Scripts/notchagent-desk-ai-visual-review-gate.sh`. This waiver can unblock the
replacement soak, but it never claims to validate physical touch latency or a
production unit's hardware interaction.

If the product owner explicitly accepts the remaining duration risk, the Beta
status records `soak-24-hours` as `waived`, bound to the immutable partial source
report and its observed health metrics. A waiver is closed for planning but is
never reported as a passed 24-hour test.
4. Touch and swipe during the 20-second telemetry window and confirm the runner.
5. Accept only exit code 0 and a report whose `result` is `accepted`; the lot gate
   recalculates every artifact hash and rejects reuse between units.
6. Generate the 50 × 30 mm unit label with
   `Scripts/notchagent-desk-unit-label.sh /absolute/label.svg LOT DESK-B1-NNN`.
   It contains only the unit alias, approved lot, firmware, and protocol—never a
   hardware serial, MAC address, USB path, credential, or customer identifier.

Before releasing a lot, run `Scripts/notchagent-desk-commercial-lot-gate.sh`
with the private procurement sheet and every QC report. It requires at least
the planned unit count, the same lot alias, unique units and unique telemetry,
then emits a private source-linked commercial evidence record. The Beta gate
recalculates it from procurement and every factory report before accepting it.

Each report binds the unit and procurement lot to the verified factory-package manifest and
its unique sanitized telemetry capture by SHA-256. The lot gate rejects stale
package manifests, repeated unit aliases, or reused telemetry evidence.

Reports persist locally under `~/Library/Application Support/NotchAgent/DeskFactoryQC`
unless `NOTCHAGENT_DESK_FACTORY_REPORT_DIR` selects another absolute private
directory. They contain aliases and health results only—never hardware serials,
customer data, provider data, credentials, or USB paths.
