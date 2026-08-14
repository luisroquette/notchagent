#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

port="${1:-}"
[[ "$port" == /dev/cu.usbmodem* && -c "$port" ]] || {
    echo "Usage: NOTCHAGENT_DESK_LOT_ALIAS=BETA1-LOT-A NOTCHAGENT_DESK_UNIT_ALIAS=DESK-B1-001 $0 /dev/cu.usbmodemXXXX" >&2
    exit 2
}
verified_port=$(NOTCHAGENT_DESK_PORT="$port" Scripts/notchagent-desk-resolve-port.sh)
[[ "$verified_port" == "$port" ]] || { echo "FAIL: port is not a NotchAgent Desk Beta 1." >&2; exit 2; }

unit_alias="${NOTCHAGENT_DESK_UNIT_ALIAS:-}"
[[ "$unit_alias" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' ]] || {
    echo "FAIL: NOTCHAGENT_DESK_UNIT_ALIAS must be 1-32 uppercase letters, digits, or hyphens." >&2
    exit 2
}
lot_alias="${NOTCHAGENT_DESK_LOT_ALIAS:-}"
[[ "$lot_alias" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' ]] || {
    echo "FAIL: NOTCHAGENT_DESK_LOT_ALIAS must identify the approved procurement lot." >&2
    exit 2
}
visual_evidence="${NOTCHAGENT_DESK_QC_VISUAL_EVIDENCE:-}"
[[ -n "$visual_evidence" ]] || {
    echo "FAIL: NOTCHAGENT_DESK_QC_VISUAL_EVIDENCE must point to this unit's private evidence." >&2
    exit 2
}
Scripts/notchagent-desk-factory-visual-gate.sh "$visual_evidence" "$lot_alias" "$unit_alias" >/dev/null
visual_evidence_sha=$(shasum -a 256 "$visual_evidence" | awk '{print $1}')

display_check="${NOTCHAGENT_DESK_QC_DISPLAY:-pending}"
touch_check="${NOTCHAGENT_DESK_QC_TOUCH:-pending}"
swipe_check="${NOTCHAGENT_DESK_QC_SWIPE:-pending}"
runner_check="${NOTCHAGENT_DESK_QC_RUNNER:-pending}"
for check in "$display_check" "$touch_check" "$swipe_check" "$runner_check"; do
    [[ "$check" == pass || "$check" == fail || "$check" == pending ]] || {
        echo "FAIL: QC checks accept only pass, fail, or pending." >&2
        exit 2
    }
done

release="firmware/notchagent_desk/release"
[[ -f "$release/manifest.json" && -f "$release/NotchAgentDesk-factory.bin" && -x "$release/esptool" ]] || {
    firmware/notchagent_desk/package-release.sh
}
firmware/notchagent_desk/verify-release.sh "$release"

if lsof "$port" >/dev/null 2>&1; then
    echo "FAIL: serial port is in use; close NotchAgent and retry." >&2
    exit 1
fi

started_at=$(date -u +%FT%TZ)
"$release/esptool" --chip esp32s3 --port "$port" --baud 921600 \
    --before default-reset --after hard-reset write-flash 0x0 \
    "$release/NotchAgentDesk-factory.bin" &
flash_pid=$!
flash_deadline=$((SECONDS + 120))
while kill -0 "$flash_pid" 2>/dev/null && (( SECONDS < flash_deadline )); do sleep 0.25; done
if kill -0 "$flash_pid" 2>/dev/null; then
    kill -TERM "$flash_pid"
    for _ in {1..40}; do
        kill -0 "$flash_pid" 2>/dev/null || break
        sleep 0.05
    done
    if kill -0 "$flash_pid" 2>/dev/null; then
        kill -KILL "$flash_pid"
    fi
    wait "$flash_pid" 2>/dev/null || true
    echo "FAIL: factory flash exceeded 120 seconds." >&2
    exit 1
fi
set +e
wait "$flash_pid"
flash_status=$?
set -e
(( flash_status == 0 )) || { echo "FAIL: factory flash failed." >&2; exit 1; }

reconnected_port=""
for _ in {1..80}; do
    reconnected_port=$(Scripts/notchagent-desk-resolve-port.sh 2>/dev/null || true)
    [[ -n "$reconnected_port" ]] && break
    sleep 0.25
done
[[ -n "$reconnected_port" ]] || { echo "FAIL: NotchAgent Desk Beta 1 did not re-enumerate." >&2; exit 1; }

report_dir="${NOTCHAGENT_DESK_FACTORY_REPORT_DIR:-${HOME:?}/Library/Application Support/NotchAgent/DeskFactoryQC}"
[[ "$report_dir" == /* ]] || {
    echo "FAIL: NOTCHAGENT_DESK_FACTORY_REPORT_DIR must be absolute." >&2
    exit 2
}
mkdir -p "$report_dir"
report_stamp=$(date -u +%Y%m%dT%H%M%SZ)
report="$report_dir/qc-${report_stamp}-$$.json"
telemetry_report="$report_dir/telemetry-${report_stamp}-$$.jsonl"
[[ ! -e "$report" && ! -e "$telemetry_report" ]] || {
    echo "FAIL: factory evidence path collision; existing reports were preserved." >&2
    exit 1
}
firmware=$(jq -r '.firmwareVersion' "$release/manifest.json")
package_manifest_sha=$(shasum -a 256 "$release/manifest.json" | awk '{print $1}')
require_touch=0
[[ "$touch_check" == pass ]] && require_touch=1
echo "Verify display, touch, swipe, and runner during the next 20 seconds."
NOTCHAGENT_DESK_PHYSICAL_TELEMETRY=1 \
NOTCHAGENT_DESK_REQUIRE_TOUCH="$require_touch" \
NOTCHAGENT_DESK_PORT="$reconnected_port" \
NOTCHAGENT_DESK_TELEMETRY_DURATION_SECONDS=20 \
NOTCHAGENT_DESK_TELEMETRY_REPORT="$telemetry_report" \
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
swift test --filter NotchAgentDeskTests/testPhysicalTelemetryWhenExplicitlyEnabled

telemetry_sha=$(shasum -a 256 "$telemetry_report" | awk '{print $1}')
telemetry_summary=$(Scripts/notchagent-desk-telemetry-evidence.sh "$telemetry_report")
result=accepted
for check in "$display_check" "$touch_check" "$swipe_check" "$runner_check"; do
    [[ "$check" == fail ]] && result=failed
    [[ "$check" == pending && "$result" != failed ]] && result=incomplete
done

jq -n \
    --arg unitAlias "$unit_alias" \
    --arg lotAlias "$lot_alias" \
    --arg startedAt "$started_at" \
    --arg completedAt "$(date -u +%FT%TZ)" \
    --arg firmwareVersion "$firmware" \
    --arg display "$display_check" \
    --arg touch "$touch_check" \
    --arg swipe "$swipe_check" \
    --arg runner "$runner_check" \
    --arg telemetrySHA256 "$telemetry_sha" \
    --arg telemetryReport "$telemetry_report" \
    --arg visualEvidenceFile "$visual_evidence" \
    --arg visualEvidenceSHA256 "$visual_evidence_sha" \
    --arg packageManifestSHA256 "$package_manifest_sha" \
    --argjson telemetry "$telemetry_summary" \
    --arg result "$result" \
    '{schemaVersion:7, lotAlias:$lotAlias, unitAlias:$unitAlias,
      startedAt:$startedAt, completedAt:$completedAt,
      firmwareVersion:$firmwareVersion, flashVerified:true, usbReenumerated:true,
      telemetryHealthy:true, checks:{display:$display,touch:$touch,swipe:$swipe,runner:$runner},
      packageManifestSHA256:$packageManifestSHA256,
      visualEvidenceFile:$visualEvidenceFile,visualEvidenceSHA256:$visualEvidenceSHA256,
      telemetryReport:$telemetryReport,telemetrySHA256:$telemetrySHA256,
      telemetry:$telemetry, result:$result}' > "$report"

echo "Report: $report"
case "$result" in
    accepted) echo "PASS: unit $unit_alias accepted." ;;
    failed) echo "FAIL: unit $unit_alias rejected by a physical check." >&2; exit 1 ;;
    incomplete) echo "INCOMPLETE: unit $unit_alias is not accepted while checks remain pending." >&2; exit 3 ;;
esac
