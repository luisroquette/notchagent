#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

report="${1:-}"
date_value="${2:-}"
dock_class="${3:-}"
dock_alias="${4:-}"
update_result="${5:-not_attempted}"
[[ -s "$report" ]] || {
    echo "Usage: $0 app-soak-report.jsonl YYYY-MM-DD direct|dock|hub connection-alias [not_attempted|pass]" >&2
    exit 2
}
[[ "$date_value" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ]] &&
  date -j -f %Y-%m-%d "$date_value" +%Y-%m-%d >/dev/null 2>&1 || {
    echo "INVALID: date must be a real YYYY-MM-DD date." >&2
    exit 2
}
[[ "$dock_class" == "direct" || "$dock_class" == "dock" || "$dock_class" == "hub" ]] || {
    echo "INVALID: dock class." >&2
    exit 2
}
[[ "$dock_alias" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' ]] || { echo "INVALID: dock alias." >&2; exit 2; }
if [[ "$dock_class" == "direct" ]]; then
    [[ "$dock_alias" == "DIRECT" ]] || { echo "INVALID: direct connection alias must be DIRECT." >&2; exit 2; }
else
    [[ "$dock_alias" != "DIRECT" ]] || { echo "INVALID: dock/hub requires a non-DIRECT alias." >&2; exit 2; }
fi
[[ "$update_result" == "not_attempted" || "$update_result" == "pass" ]] || {
    echo "INVALID: update result." >&2
    exit 2
}

jq -s -e '
  [.[] | select(.phase == "connected" and .telemetry != null)] as $samples |
  ($samples[0].elapsedMilliseconds // -1) as $first |
  ($samples[-1].elapsedMilliseconds // -1) as $last |
  ([range(1; $samples|length) as $index |
    $samples[$index].elapsedMilliseconds - $samples[$index - 1].elapsedMilliseconds] | max // 0) as $maxGap |
  ($samples | length) >= 2 and
  $first >= 0 and $last >= $first and $maxGap <= 10000 and
  all(.[] | select(.elapsedMilliseconds >= $first and .elapsedMilliseconds <= $last);
    .phase == "connected") and
  all($samples[];
    .firmwareVersion == "0.6.16" and .telemetry.firmwareVersion == "0.6.16" and
    (.reliabilityFailures | length) == 0 and
    .telemetry.touchControllerPresent == true)
' "$report" >/dev/null || { echo "INVALID: report lacks connected firmware 0.6.16 telemetry." >&2; exit 1; }
report_sha=$(shasum -a 256 "$report" | awk '{print $1}')

jq -s \
  --arg date "$date_value" \
  --arg dockClass "$dock_class" \
  --arg dockAlias "$dock_alias" \
  --arg updateResult "$update_result" \
  --arg sourceReport "$report" \
  --arg sourceReportSHA256 "$report_sha" '
  [.[] | select(.phase == "connected" and .telemetry != null)] as $samples |
  ($samples[0].elapsedMilliseconds / 1000) as $connectionSeconds |
  (["panic","interrupt_watchdog","task_watchdog","watchdog","brownout"] as $unsafe |
    [$samples[].telemetry.resetReason | select(. as $reason | $unsafe | index($reason))] | unique | length) as $anomalies |
  ($samples | map(.telemetry.touchCount // 0) | min) as $firstTouchCount |
  ($samples | map(.telemetry.touchCount // 0) | max) as $lastTouchCount |
  ($lastTouchCount > $firstTouchCount) as $touchObserved |
  ($samples | map(.telemetry.maximumTouchLatencyMs // 0) | max) as $touchLatency |
  {date:$date, connectionSuccess:true, connectionSeconds:$connectionSeconds,
   dockClass:$dockClass, dockAlias:$dockAlias, firmwareVersion:"0.6.16",
   healthPass:($anomalies == 0 and
     ($samples | map(.telemetry.minimumFreeHeapBytes) | min) >= 122880 and
     ($samples | map(.telemetry.framesPerSecond) | min) >= 7 and
     $touchObserved and $touchLatency > 0 and $touchLatency <= 100 and
     ($samples | map(.telemetry.invalidFrameCount) | max) == 0 and
     ($samples | map(.telemetry.touchReadErrorCount // 0) | max) == 0),
   resetAnomalyCount:$anomalies,
   minimumFreeHeapBytes:($samples | map(.telemetry.minimumFreeHeapBytes) | min),
   minimumFramesPerSecond:($samples | map(.telemetry.framesPerSecond) | min),
   maximumTouchLatencyMs:$touchLatency,
   sourceReport:$sourceReport,
   sourceReportSHA256:$sourceReportSHA256,
   touchObserved:$touchObserved,
   updateResult:$updateResult}
' "$report"
