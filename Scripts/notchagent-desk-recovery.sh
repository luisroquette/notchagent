#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

app="${NOTCHAGENT_DESK_RECOVERY_APP:-dist/NotchAgent.app}"
[[ "$app" == /* || "$app" == "dist/NotchAgent.app" ]] || {
    echo "FAIL: NOTCHAGENT_DESK_RECOVERY_APP must be an absolute app path." >&2
    exit 2
}
info="$app/Contents/Info.plist"
package="$app/Contents/Resources/DeskFirmware"
[[ -d "$app" && -f "$info" && -d "$package" ]] || {
    echo "NOT READY: build the NotchAgent Desk Beta 1 app first." >&2
    exit 2
}

running_app=$(pgrep -x NotchAgent 2>/dev/null | head -1 || true)
[[ -z "$running_app" ]] || {
    echo "FAIL: quit NotchAgent before the physical recovery test." >&2
    exit 1
}
port=$(Scripts/notchagent-desk-resolve-port.sh)
[[ -z "$(lsof -t "$port" 2>/dev/null | head -1 || true)" ]] || {
    echo "FAIL: serial port is in use: $port" >&2
    exit 1
}

signature_details=$(codesign -dv --verbose=4 "$app" 2>&1)
authority=$(print -r -- "$signature_details" | sed -n 's/^Authority=//p' | head -1)
[[ "$authority" == "Developer ID Application:"* ]] || {
    echo "NOT READY: recovery must use the Developer ID signed Beta 1 app." >&2
    exit 1
}
codesign --verify --deep --strict --verbose=2 "$app"
[[ "$signature_details" =~ 'flags=.*runtime' ]] || {
    echo "NOT READY: hardened runtime is missing." >&2
    exit 1
}

app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")
[[ "$app_version" == "3.1.1" && "$build_number" == "4" ]] || {
    echo "NOT READY: expected NotchAgent 3.1.1 build 4." >&2
    exit 1
}
firmware/notchagent_desk/verify-release.sh "$package" >/dev/null
[[ "$(jq -r '.firmwareVersion' "$package/manifest.json")" == "0.6.16" ]] || {
    echo "NOT READY: bundled recovery firmware must be 0.6.16." >&2
    exit 1
}

report_dir="${NOTCHAGENT_DESK_RECOVERY_REPORT_DIR:-${HOME:?}/Library/Application Support/NotchAgent/DeskRecovery}"
[[ "$report_dir" == /* ]] || { echo "FAIL: recovery report directory must be absolute." >&2; exit 2; }
mkdir -p "$report_dir"
report_stamp=$(date -u +%Y%m%dT%H%M%SZ)
telemetry_report="$report_dir/telemetry-${report_stamp}-$$.jsonl"
report="$report_dir/recovery-${report_stamp}-$$.json"
[[ ! -e "$telemetry_report" && ! -e "$report" ]] || {
    echo "FAIL: recovery evidence path collision; prior evidence was preserved." >&2
    exit 1
}
started_at=$(date -u +%FT%TZ)
started_seconds=$SECONDS

NOTCHAGENT_DESK_PHYSICAL_UPDATE=1 \
NOTCHAGENT_DESK_PORT="$port" \
NOTCHAGENT_DESK_PACKAGE_DIR="$package" \
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
swift test --filter NotchAgentDeskTests/testPhysicalFirmwareUpdateWhenExplicitlyEnabled

reconnected_port=""
for _ in {1..120}; do
    reconnected_port=$(Scripts/notchagent-desk-resolve-port.sh 2>/dev/null || true)
    [[ -n "$reconnected_port" ]] && break
    sleep 0.25
done
[[ -n "$reconnected_port" ]] || { echo "FAIL: Desk did not re-enumerate after recovery." >&2; exit 1; }

NOTCHAGENT_DESK_PHYSICAL_TELEMETRY=1 \
NOTCHAGENT_DESK_PORT="$reconnected_port" \
NOTCHAGENT_DESK_TELEMETRY_DURATION_SECONDS=10 \
NOTCHAGENT_DESK_TELEMETRY_REPORT="$telemetry_report" \
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
swift test --filter NotchAgentDeskTests/testPhysicalTelemetryWhenExplicitlyEnabled

duration_seconds=$((SECONDS - started_seconds))
telemetry_sha=$(shasum -a 256 "$telemetry_report" | awk '{print $1}')
manifest_sha=$(shasum -a 256 "$package/manifest.json" | awk '{print $1}')
executable_sha=$(shasum -a 256 "$app/Contents/MacOS/NotchAgent" | awk '{print $1}')
telemetry_summary=$(Scripts/notchagent-desk-telemetry-evidence.sh "$telemetry_report")
telemetry_evidence_path="$telemetry_report"
[[ "$telemetry_report" != "$PWD/"* ]] || telemetry_evidence_path="${telemetry_report#$PWD/}"
jq -n \
  --arg startedAt "$started_at" \
  --arg completedAt "$(date -u +%FT%TZ)" \
  --arg appVersion "$app_version" \
  --arg buildNumber "$build_number" \
  --argjson durationSeconds "$duration_seconds" \
  --arg telemetryReport "$telemetry_evidence_path" \
  --arg telemetrySHA256 "$telemetry_sha" \
  --arg packageManifestSHA256 "$manifest_sha" \
  --arg executableSHA256 "$executable_sha" \
  --argjson telemetry "$telemetry_summary" \
  '{schemaVersion:2, gate:"local-signed-recovery", result:"pass",
    startedAt:$startedAt, completedAt:$completedAt, durationSeconds:$durationSeconds,
    appVersion:$appVersion, buildNumber:$buildNumber, firmwareVersion:"0.6.16",
    protocolVersion:"1.1", signatureKind:"Developer ID Application", hardenedRuntime:true,
    usbReenumerated:true, telemetryHealthy:true, telemetryReport:$telemetryReport,
    telemetrySHA256:$telemetrySHA256,
    packageManifestSHA256:$packageManifestSHA256, executableSHA256:$executableSHA256,
    telemetry:$telemetry}' > "$report"

echo "PASS: signed local recovery completed with healthy post-flash telemetry in ${duration_seconds}s."
echo "Report: $report"
