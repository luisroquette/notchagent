#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

duration_seconds="${1:-86400}"
[[ "$duration_seconds" =~ '^[1-9][0-9]*$' ]] || {
    echo "Usage: $0 [duration-seconds]" >&2
    exit 2
}

port=$(Scripts/notchagent-desk-resolve-port.sh)
app="dist/NotchAgent.app/Contents/MacOS/NotchAgent"
[[ -x "$app" ]] || { echo "FAIL: build dist/NotchAgent.app first." >&2; exit 1; }
app_bundle="dist/NotchAgent.app"
app_firmware_dir="$app_bundle/Contents/Resources/DeskFirmware"
app_firmware_manifest="$app_firmware_dir/manifest.json"
release_manifest="firmware/notchagent_desk/release/manifest.json"
release_contract="docs/NOTCHAGENT_DESK_RELEASE.json"
for required_file in "$app_firmware_manifest" "$release_manifest" "$release_contract"; do
    [[ -f "$required_file" ]] || { echo "FAIL: candidate metadata missing: $required_file" >&2; exit 1; }
done
app_version=$(plutil -extract CFBundleShortVersionString raw "$app_bundle/Contents/Info.plist")
build_number=$(plutil -extract CFBundleVersion raw "$app_bundle/Contents/Info.plist")
firmware_image_sha=$(jq -er '.imageSHA256' "$release_manifest")
firmware_source_sha=$(jq -er '.sourceSHA256' "$release_manifest")
jq -e --arg appVersion "$app_version" --arg buildNumber "$build_number" \
  --slurpfile package "$release_manifest" --slurpfile bundled "$app_firmware_manifest" '
  .appVersion == $appVersion and .buildNumber == $buildNumber and
  .firmwareVersion == $package[0].firmwareVersion and
  $package[0].schemaVersion == 2 and $bundled[0].schemaVersion == 2 and
  $bundled[0].firmwareVersion == $package[0].firmwareVersion and
  $bundled[0].imageSHA256 == $package[0].imageSHA256 and
  $bundled[0].sourceSHA256 == $package[0].sourceSHA256
' "$release_contract" >/dev/null || {
    echo "FAIL: app, firmware package, and Beta release contract identify different candidates." >&2
    exit 1
}
cmp -s "$app_firmware_dir/NotchAgentDesk-factory.bin" \
  firmware/notchagent_desk/release/NotchAgentDesk-factory.bin || {
    echo "FAIL: bundled and factory firmware images differ." >&2
    exit 1
}
running_app=$(pgrep -x NotchAgent 2>/dev/null | head -1 || true)
[[ -z "$running_app" ]] || { echo "FAIL: quit every running NotchAgent instance before starting the soak." >&2; exit 1; }
owner=$(lsof -t "$port" 2>/dev/null | head -1 || true)
[[ -z "$owner" ]] || { echo "FAIL: quit the running NotchAgent before starting the soak." >&2; exit 1; }

report_dir="${NOTCHAGENT_DESK_REPORT_DIR:-${TMPDIR:-/tmp}/notchagent-desk-soak}"
[[ "$report_dir" == /* ]] || { echo "FAIL: report directory must be absolute." >&2; exit 2; }
mkdir -p "$report_dir"
pid_file="$report_dir/soak-active.pid"
report_pointer="$report_dir/soak-active-report.txt"
if [[ -f "$pid_file" ]]; then
    prior_pid=$(tr -d '[:space:]' < "$pid_file")
    if [[ "$prior_pid" =~ '^[0-9]+$' ]] && kill -0 "$prior_pid" 2>/dev/null; then
        echo "FAIL: soak already active with PID $prior_pid." >&2
        exit 1
    fi
fi
report="$report_dir/soak-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
summary="$report_dir/summary-$(date -u +%Y%m%dT%H%M%SZ).json"
print -r -- "$$" > "$pid_file"
report_pointer_value="$report"
[[ "$report" != "$PWD/"* ]] || report_pointer_value="${report#$PWD/}"
print -r -- "$report_pointer_value" > "$report_pointer"

NOTCHAGENT_DESK_SOAK_REPORT="$report" \
NOTCHAGENT_DISABLE_PAID_PROBES=1 \
"$app" --desk-soak &
app_pid=$!

cleanup() {
    if kill -0 "$app_pid" 2>/dev/null; then
        kill -TERM "$app_pid"
        for _ in {1..50}; do
            kill -0 "$app_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -0 "$app_pid" 2>/dev/null && {
            echo "FAIL: NotchAgent did not stop after SIGTERM." >&2
            return 1
        }
    fi
    if [[ -f "$pid_file" && "$(tr -d '[:space:]' < "$pid_file")" == "$$" ]]; then
        rm -- "$pid_file" "$report_pointer"
    fi
    return 0
}
trap 'cleanup || true' EXIT INT TERM

fail_soak() {
    local reason="$1"
    local report_sha=""
    [[ -f "$report" ]] && report_sha=$(shasum -a 256 "$report" | awk '{print $1}')
    jq -n \
      --arg reason "$reason" \
      --arg failedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg reportSHA256 "$report_sha" \
      --arg report "$report" \
      '{schemaVersion:1, result:"fail", reason:$reason, failedAt:$failedAt,
        report:$report, reportSHA256:$reportSHA256}' > "$summary"
    echo "FAIL: $reason" >&2
    echo "Failure summary: $summary" >&2
    exit 1
}

deadline=$((SECONDS + duration_seconds))
startup_deadline=$((SECONDS + 15))
last_checked_line=0
connected_seen=false
while (( SECONDS < deadline )); do
    kill -0 "$app_pid" 2>/dev/null || fail_soak "NotchAgent exited during soak."
    if [[ -s "$report" ]]; then
        modified=$(stat -f %m "$report")
        now=$(date +%s)
        age=$((now - modified))
        (( age <= 15 )) || fail_soak "soak report stopped advancing for ${age}s."
        line_count=$(wc -l < "$report" | tr -d '[:space:]')
        if (( line_count > last_checked_line )); then
            while IFS= read -r record; do
                phase=$(jq -r '.phase // "missing"' <<<"$record")
                telemetry_present=$(jq -r '(.telemetry // null) != null' <<<"$record")
                if [[ "$connected_seen" == true && "$phase" != "connected" ]]; then
                    fail_soak "Desk left connected state: $phase."
                fi
                if [[ "$phase" == "connected" && "$telemetry_present" == true ]]; then
                    connected_seen=true
                fi
            done < <(sed -n "$((last_checked_line + 1)),${line_count}p" "$report")
            last_checked_line=$line_count
        fi
        if (( SECONDS >= startup_deadline )); then
            [[ "$connected_seen" == true ]] || fail_soak "Desk did not reach connected telemetry within 15s."
        fi
    elif (( SECONDS >= startup_deadline )); then
        fail_soak "NotchAgent produced no soak records within 15s."
    fi
    sleep 1
done
cleanup || exit 1
wait "$app_pid" 2>/dev/null || true
trap - EXIT INT TERM

expected_samples=$((duration_seconds / 10))
(( expected_samples >= 1 )) || expected_samples=1
jq -s -e --argjson expected "$expected_samples" --argjson duration "$duration_seconds" '
  [.[] | select(.telemetry != null)] as $samples |
  ($samples[0].elapsedMilliseconds // -1) as $first |
  ($samples[-1].elapsedMilliseconds // -1) as $last |
  ([range(1; $samples|length) as $index |
    $samples[$index].elapsedMilliseconds - $samples[$index - 1].elapsedMilliseconds] | max // 0) as $maxGap |
  ($samples | length) >= $expected and
  $first >= 0 and $first <= 10000 and
  $last >= (($duration * 1000) - 10000) and
  $maxGap <= 16000 and
  all($samples[]; (.reliabilityFailures | length) == 0) and
  all(.[] | select(.elapsedMilliseconds >= $first and .elapsedMilliseconds <= $last); .phase == "connected")
' "$report" >/dev/null || { echo "FAIL: app soak violated connection or telemetry gates." >&2; exit 1; }

Scripts/notchagent-desk-soak-evidence.sh "$report" "$duration_seconds" > "$summary"

echo "PASS: NotchAgent app and Desk remained healthy for ${duration_seconds}s"
echo "Report: $report"
echo "Summary: $summary"
