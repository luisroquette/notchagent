#!/bin/zsh
set -euo pipefail

duration_seconds="${1:-45}"
[[ "$duration_seconds" =~ '^[1-9][0-9]*$' ]] || {
    echo "Usage: $0 [duration-seconds] [live-soak-report.jsonl]" >&2
    exit 2
}

report_dir="${NOTCHAGENT_DESK_REPORT_DIR:-${HOME:?}/Library/Application Support/NotchAgent/DeskReliability}"
explicit_report="${2:-}"
report_pointer="$report_dir/soak-active-report.txt"
if [[ -n "$explicit_report" ]]; then
    report="$explicit_report"
elif [[ -f "$report_pointer" ]]; then
    report=$(head -1 "$report_pointer")
else
    report=""
fi
[[ -f "$report" ]] || { echo "FAIL: no live Desk soak report found." >&2; exit 1; }
if [[ -z "$explicit_report" ]]; then
    pid_file="$report_dir/soak-active.pid"
    [[ -f "$pid_file" ]] || { echo "FAIL: no active soak PID file found." >&2; exit 1; }
    soak_pid=$(tr -d '[:space:]' < "$pid_file")
    [[ "$soak_pid" =~ '^[0-9]+$' ]] || { echo "FAIL: invalid soak PID." >&2; exit 1; }
    kill -0 "$soak_pid" 2>/dev/null || { echo "FAIL: the selected soak is no longer running." >&2; exit 1; }
    modified=$(stat -f %m "$report")
    now=$(date +%s)
    (( now - modified <= 10 )) || { echo "FAIL: live soak report has not advanced for more than 10s." >&2; exit 1; }
fi

telemetry_json() {
    jq -s -c '[.[] | select(.telemetry != null)][-1].telemetry // empty' "$report"
}

baseline=$(telemetry_json)
[[ -n "$baseline" ]] || { echo "FAIL: live soak has no telemetry yet." >&2; exit 1; }
baseline_touches=$(jq -r '.touchCount' <<<"$baseline")
echo "Touch and swipe the Desk during the next ${duration_seconds}s."

deadline=$((SECONDS + duration_seconds))
touch_seen=false
last_touches="$baseline_touches"
stable_since=0
while (( SECONDS < deadline )); do
    current=$(telemetry_json)
    if [[ -n "$current" ]]; then
        touches=$(jq -r '.touchCount' <<<"$current")
        if (( touches > baseline_touches )); then
            touch_seen=true
            latency=$(jq -r '.maximumTouchLatencyMs' <<<"$current")
            controller=$(jq -r '.touchControllerPresent // false' <<<"$current")
            errors=$(jq -r '.touchReadErrorCount // 0' <<<"$current")
            jq -e '
              (.touchControllerPresent == true) and
              ((.touchReadErrorCount // 0) == 0) and
              (.maximumTouchLatencyMs <= 100)
            ' <<<"$current" >/dev/null || {
                echo "FAIL: touch detected but health/latency gate failed: controller=$controller errors=$errors latency=${latency}ms" >&2
                exit 1
            }
            if (( touches == last_touches )); then
                (( stable_since > 0 )) || stable_since=$SECONDS
                if (( SECONDS - stable_since >= 10 )); then
                    echo "PASS: touch and release detected; latency=${latency}ms IRQ=$(jq -r '.touchInterruptCount // 0' <<<"$current") poll=$(jq -r '.touchPollTouchCount // 0' <<<"$current")"
                    exit 0
                fi
            else
                stable_since=0
            fi
            last_touches="$touches"
        fi
    fi
    sleep 1
done

final=$(telemetry_json)
if [[ "$touch_seen" == true ]]; then
    echo "FAIL: touch was detected but the counter did not stabilize for 10s after release." >&2
    exit 1
fi
echo "FAIL: no new touch; controller=$(jq -r '.touchControllerPresent // false' <<<"$final") IRQ=$(jq -r '.touchInterruptCount // 0' <<<"$final") polls=$(jq -r '.touchPollAttemptCount // 0' <<<"$final") errors=$(jq -r '.touchReadErrorCount // 0' <<<"$final")" >&2
exit 1
