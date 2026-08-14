#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

disconnect_timeout="${1:-120}"
reconnect_timeout="${2:-120}"
[[ "$disconnect_timeout" =~ '^[1-9][0-9]*$' && "$reconnect_timeout" =~ '^[1-9][0-9]*$' ]] || {
    echo "Usage: $0 [disconnect-timeout-seconds] [reconnect-timeout-seconds]" >&2
    exit 2
}

port=$(Scripts/notchagent-desk-resolve-port.sh)
release_package="firmware/notchagent_desk/release"
firmware/notchagent_desk/verify-release.sh "$release_package" >/dev/null
firmware_version=$(jq -er '.firmwareVersion' "$release_package/manifest.json")
firmware_image_sha=$(jq -er '.imageSHA256' "$release_package/manifest.json")
firmware_source_sha=$(jq -er '.sourceSHA256' "$release_package/manifest.json")
[[ "$firmware_version" == "0.6.16" ]] || {
    echo "FAIL: abrupt power recovery requires the Beta 1 firmware package." >&2
    exit 1
}
owner=$(lsof -t "$port" 2>/dev/null | head -1 || true)
[[ -z "$owner" ]] || {
    echo "FAIL: $port is in use. Quit NotchAgent before the power-cycle test." >&2
    exit 1
}

report_dir="${NOTCHAGENT_DESK_POWER_REPORT_DIR:-${HOME:?}/Library/Application Support/NotchAgent/DeskPowerCycle}"
[[ "$report_dir" == /* ]] || { echo "FAIL: power report directory must be absolute." >&2; exit 2; }
mkdir -p "$report_dir"
started_at=$(date -u +%FT%TZ)
started_seconds=$SECONDS
echo "Disconnect the Desk power/data cable within ${disconnect_timeout}s."
disconnect_deadline=$((SECONDS + disconnect_timeout))
missing_samples=0
while (( SECONDS < disconnect_deadline )); do
    if [[ ! -c "$port" ]]; then
        (( missing_samples += 1 ))
        (( missing_samples >= 4 )) && break
    else
        missing_samples=0
    fi
    sleep 0.25
done
(( missing_samples >= 4 )) || { echo "FAIL: physical USB disconnect was not observed." >&2; exit 1; }
disconnected_at=$(date -u +%FT%TZ)
disconnect_observed_after_seconds=$((SECONDS - started_seconds))
disconnected_seconds=$SECONDS

echo "Reconnect the Desk cable within ${reconnect_timeout}s."
reconnect_deadline=$((SECONDS + reconnect_timeout))
reconnected_port=""
while (( SECONDS < reconnect_deadline )); do
    reconnected_port=$(Scripts/notchagent-desk-resolve-port.sh 2>/dev/null || true)
    [[ -n "$reconnected_port" ]] && break
    sleep 0.25
done
[[ -n "$reconnected_port" ]] || { echo "FAIL: exactly one NotchAgent Desk Beta 1 did not re-enumerate." >&2; exit 1; }
reconnected_at=$(date -u +%FT%TZ)
reconnect_seconds=$((SECONDS - disconnected_seconds))

telemetry_stamp=$(date -u +%Y%m%dT%H%M%SZ)
telemetry_report="$report_dir/telemetry-${telemetry_stamp}-$$.jsonl"
[[ ! -e "$telemetry_report" ]] || {
    echo "FAIL: power-cycle telemetry path collision; prior evidence was preserved." >&2
    exit 1
}
NOTCHAGENT_DESK_PHYSICAL_TELEMETRY=1 \
NOTCHAGENT_DESK_PORT="$reconnected_port" \
NOTCHAGENT_DESK_TELEMETRY_DURATION_SECONDS=10 \
NOTCHAGENT_DESK_TELEMETRY_REPORT="$telemetry_report" \
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
swift test --filter NotchAgentDeskTests/testPhysicalTelemetryWhenExplicitlyEnabled

telemetry_sha=$(shasum -a 256 "$telemetry_report" | awk '{print $1}')
telemetry_summary=$(Scripts/notchagent-desk-telemetry-evidence.sh "$telemetry_report" power_on)
report_stamp=$(date -u +%Y%m%dT%H%M%SZ)
report="$report_dir/power-cycle-${report_stamp}-$$.json"
[[ ! -e "$report" ]] || {
    echo "FAIL: power-cycle report path collision; prior evidence was preserved." >&2
    exit 1
}
jq -n \
    --arg startedAt "$started_at" \
    --arg disconnectedAt "$disconnected_at" \
    --arg reconnectedAt "$reconnected_at" \
    --arg completedAt "$(date -u +%FT%TZ)" \
    --arg telemetryReport "$telemetry_report" \
    --arg telemetrySHA256 "$telemetry_sha" \
    --arg firmwareImageSHA256 "$firmware_image_sha" \
    --arg firmwareSourceSHA256 "$firmware_source_sha" \
    --argjson disconnectObservedAfterSeconds "$disconnect_observed_after_seconds" \
    --argjson reconnectSeconds "$reconnect_seconds" \
    --argjson telemetry "$telemetry_summary" \
    '{schemaVersion:3, gate:"abrupt-power-recovery", startedAt:$startedAt, disconnectedAt:$disconnectedAt,
      reconnectedAt:$reconnectedAt, completedAt:$completedAt,
      disconnectObservedAfterSeconds:$disconnectObservedAfterSeconds,
      reconnectSeconds:$reconnectSeconds, firmwareVersion:"0.6.16", protocolVersion:"1.1",
      firmwareImageSHA256:$firmwareImageSHA256,firmwareSourceSHA256:$firmwareSourceSHA256,
      usbReenumerated:true, telemetryHealthy:true, telemetryReport:$telemetryReport,
      telemetrySHA256:$telemetrySHA256,
      telemetry:$telemetry, result:"pass"}' > "$report"

echo "PASS: abrupt physical power loss recovered with healthy telemetry."
echo "Report: $report"
