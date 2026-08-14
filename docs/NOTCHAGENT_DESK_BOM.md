# NotchAgent Desk Beta 1 BOM

This BOM separates verified engineering requirements from purchasing decisions
that still require a supplier sample and owner approval.

## Verified core

| Item | Requirement | Status |
|---|---|---|
| Display controller | Guition JC4832W535, ESP32-S3, 480x320 touch, AXS15231B | Verified on prototype |
| Flash / PSRAM | 16 MB flash, 8 MB OPI PSRAM | Verified by connected prototype |
| Data link | Any USB data cable compatible with the board connector and the customer's Mac/dock | Verified function; commodity item, no fixed SKU |
| Firmware | NotchAgent Desk factory image, protocol v1.1 | Build and recovery flow validated |
| Mac software | NotchAgent macOS 14+ app with Desk firmware package | Build validated; notarization and public download pending |

## Purchasing gates

For Beta 1, the product owner explicitly accepted commodity sourcing for the
USB data cable and enclosure. Their supplier and SKU may vary between units or
lots; functional QC remains mandatory. A cable must transfer data, and an
enclosure must preserve connector, touch, ventilation, and boot access. The
waiver is retained with the local release evidence and is not published.

Do not freeze a supplier or SKU until a sample passes factory QC, the 24-hour
soak test, 100 reconnect cycles, fit inspection, and cable data/charge testing.
Record supplier, SKU, unit cost, lead time, minimum order, order quantity, and sample result in
the private purchasing sheet; do not commit customer or supplier identifiers.
Each item also requires a private, non-symlinked inspection JSON tied by SHA-256,
with an inspector alias, UTC timestamp, at least two unique photo hashes, and
item-specific checks. A typed `samplePassed` flag alone is never evidence.
Start each inspection from `docs/NOTCHAGENT_DESK_SAMPLE_EVIDENCE_TEMPLATE.json`.
Every photo path must point to a nonempty PNG, JPEG, or HEIC regular file; the
gate recalculates its SHA-256 and rejects reuse across procurement items.
Use `docs/NOTCHAGENT_DESK_PROCUREMENT_TEMPLATE.json` as the private sheet
contract and validate it with `Scripts/notchagent-desk-procurement-gate.sh`.
The gate refuses placeholder SKUs, zero costs, untested samples, charge-only
cables, obstructed enclosures, or packaging without onboarding and recovery.
It also enforces whole-unit quantities at or above the planned lot, MOQ multiples,
lead times, and a closed schema that
rejects unexpected supplier, customer, credential, or free-form fields.
`Scripts/notchagent-desk-commercial-lot-gate.sh` is the final join: it refuses
a factory lot unless its QC reports match this procurement lot and cover every
planned unit. Its private evidence retains every source path and SHA-256; the
Beta gate revalidates the sources and recalculates the complete lot summary.

## Enclosure and packaging gates

- Enclosure must expose the USB connector without stressing the PCB.
- Touch surface, viewing angle, ventilation, and reset/boot access must remain usable.
- Include one known-good data cable; charge-only cables are not acceptable.
- Include the onboarding QR and a recovery instruction card only after the QR
  destination exposes the signed app download and Desk setup steps.
- Assign a non-hardware unit alias such as `DESK-B1-001`; factory reports use
  this alias and never the USB path, MAC address, provider data, or customer data.
- Print its label with `Scripts/notchagent-desk-unit-label.sh`; do not add a
  supplier serial, MAC address, USB path, or customer identifier.

## Factory acceptance

Run `Scripts/notchagent-desk-factory-qc.sh` with the unit alias, the same
`NOTCHAGENT_DESK_LOT_ALIAS` approved by procurement, and explicit
`pass`, `fail`, or `pending` values for display, touch, swipe, and runner. The
script validates the release manifest and payload hashes, flashes the package,
verifies USB re-enumeration, captures healthy
telemetry, and fails closed: a unit is accepted only when all four physical
checks are `pass`.
The station procedure is in `docs/NOTCHAGENT_DESK_FACTORY.md`. QC reports are
persistent and `Scripts/notchagent-desk-factory-report-gate.sh` validates unique
accepted units before a lot advances.

For distribution, build with `NOTCHAGENT_SIGN_IDENTITY="Developer ID Application: …"`.
Use `Scripts/make-notchagent-desk-beta1.sh`; it enforces the release contract
in `docs/NOTCHAGENT_DESK_RELEASE.json` (app 3.1.1 build 4, firmware 0.6.16,
protocol 1.1) and enables hardened runtime. Then run
`Scripts/notarize-app.sh` with a `notarytool` Keychain profile; it refuses Apple
Development/ad-hoc signatures, validates the staple and Gatekeeper result, and
writes the final stapled `NotchAgent-Desk-Beta1-3.1.1.zip`. Its sanitized
evidence binds that exact ZIP by SHA-256 to the onboarding publication record,
without storing the signing identity, Team ID, Keychain profile, or notarization
submission identifier. Existing evidence or release assets are never overwritten.
After the guide and release are public, run
`Scripts/notchagent-desk-publication-evidence.sh`; it live-downloads both from
GitHub and refuses to pass unless the published ZIP has the notarized SHA-256,
one Developer ID app, hardened runtime, valid staple, Gatekeeper acceptance,
the notarized executable, and the verified embedded firmware package.
