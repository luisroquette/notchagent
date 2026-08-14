#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

report="${1:-}"
tap="${2:-pending}"
swipe_left="${3:-pending}"
swipe_right="${4:-pending}"
runner_jump="${5:-pending}"
source_label="${6:-$report}"
[[ -f "$report" && ! -L "$report" && -n "$source_label" ]] || {
    echo "Usage: $0 touch-source.jsonl tap swipe-left swipe-right runner-jump [source-label]" >&2
    exit 2
}
for result in "$tap" "$swipe_left" "$swipe_right" "$runner_jump"; do
    [[ "$result" == pass || "$result" == fail || "$result" == pending ]] || {
        echo "INVALID: physical results accept only pass, fail, or pending." >&2
        exit 2
    }
done

latest=$(jq -s -c '[.[] | select(.telemetry != null)][-1] // empty' "$report")
[[ -n "$latest" ]] || { echo "INVALID: report contains no touch telemetry." >&2; exit 1; }
jq -e '
  .firmwareVersion == "0.6.16" and .protocolMajor == 1 and .protocolMinor == 1 and
  .telemetry.firmwareVersion == "0.6.16" and .telemetry.touchControllerPresent == true and
  .telemetry.touchCount > 0 and
  ((.telemetry.touchInterruptCount // 0) > 0 or (.telemetry.touchPollTouchCount // 0) > 0) and
  (.telemetry.touchReadErrorCount // 0) == 0 and .telemetry.maximumTouchLatencyMs <= 100 and
  (.reliabilityFailures | length) == 0 and
  (.capturedAt | fromdateiso8601 | type) == "number"
' <<<"$latest" >/dev/null || {
    echo "INVALID: physical touch telemetry is missing or unhealthy." >&2
    exit 1
}

final_status=pass
for result in "$tap" "$swipe_left" "$swipe_right" "$runner_jump"; do
    [[ "$result" == fail ]] && final_status=fail
    [[ "$result" == pending && "$final_status" != fail ]] && final_status=pending
done
report_sha=$(shasum -a 256 "$report" | awk '{print $1}')
jq -n --arg status "$final_status" --arg capturedAt "$(jq -r '.capturedAt' <<<"$latest")" \
  --argjson telemetry "$(jq -c '.telemetry' <<<"$latest")" \
  --arg tap "$tap" --arg swipeLeft "$swipe_left" --arg swipeRight "$swipe_right" \
  --arg runnerJump "$runner_jump" --arg sourceReport "$source_label" --arg reportSHA "$report_sha" '
  {schemaVersion:1,gate:"physical-touch-latency",status:$status,capturedAt:$capturedAt,
   firmwareVersion:$telemetry.firmwareVersion,touchControllerPresent:$telemetry.touchControllerPresent,
   touchCount:$telemetry.touchCount,touchInterruptCount:($telemetry.touchInterruptCount // 0),
   touchPollTouchCount:($telemetry.touchPollTouchCount // 0),
   touchReadErrorCount:($telemetry.touchReadErrorCount // 0),
   maximumTouchLatencyMs:$telemetry.maximumTouchLatencyMs,maximumAllowedTouchLatencyMs:100,
   physicalChecks:{tap:$tap,swipeLeft:$swipeLeft,swipeRight:$swipeRight,runnerJump:$runnerJump},
   reliabilityFailures:[],sourceReport:$sourceReport,sourceReportSHA256:$reportSHA}
'
