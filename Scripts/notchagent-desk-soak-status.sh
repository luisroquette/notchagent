#!/bin/zsh
set -euo pipefail

report_dir="${NOTCHAGENT_DESK_REPORT_DIR:-${HOME:?}/Library/Application Support/NotchAgent/DeskReliability}"
max_stale_seconds="${NOTCHAGENT_DESK_SOAK_MAX_STALE_SECONDS:-15}"
[[ "$max_stale_seconds" =~ '^[1-9][0-9]*$' ]] || {
    echo "INVALID: NOTCHAGENT_DESK_SOAK_MAX_STALE_SECONDS must be a positive integer." >&2
    exit 2
}
pid_file="$report_dir/soak-active.pid"
report_pointer="$report_dir/soak-active-report.txt"
[[ -f "$pid_file" && -f "$report_pointer" ]] || { echo "NOT RUNNING: no supervised soak metadata."; exit 1; }
pid=$(tr -d '[:space:]' < "$pid_file")
report=$(head -1 "$report_pointer")
[[ "$pid" =~ '^[0-9]+$' && -f "$report" ]] || { echo "NOT RUNNING: invalid soak metadata." >&2; exit 1; }
kill -0 "$pid" 2>/dev/null || { echo "NOT RUNNING: soak process exited." >&2; exit 1; }

modified=$(stat -f %m "$report")
now=$(date +%s)
seconds_since_last_record=$((now - modified))
(( seconds_since_last_record >= 0 )) || seconds_since_last_record=0
last_phase=$(jq -s -r '.[-1].phase // "missing"' "$report")
connection_continuity=$(jq -s -r '
  ([.[] | select(.telemetry != null)][0].elapsedMilliseconds // null) as $first |
  if $first == null then false
  else all(.[] | select(.elapsedMilliseconds >= $first); .phase == "connected")
  end
' "$report")
reliability_failure_count=$(jq -s '[.[].reliabilityFailures[]] | length' "$report")
maximum_sample_gap_milliseconds=$(jq -s '
  [.[] | select(.telemetry != null)] as $samples |
  [range(1; $samples|length) as $index |
    $samples[$index].elapsedMilliseconds - $samples[$index - 1].elapsedMilliseconds] | max // 0
' "$report")
minimum_wall_clock_gap_seconds=$(jq -s '
  [.[] | select(.telemetry != null) | (.capturedAt | fromdateiso8601)] as $times |
  [range(1; $times|length) as $index | $times[$index] - $times[$index - 1]] | min // 0
' "$report")
maximum_wall_clock_gap_seconds=$(jq -s '
  [.[] | select(.telemetry != null) | (.capturedAt | fromdateiso8601)] as $times |
  [range(1; $times|length) as $index | $times[$index] - $times[$index - 1]] | max // 0
' "$report")
healthy=true
(( seconds_since_last_record <= max_stale_seconds )) || healthy=false
[[ "$last_phase" == "connected" ]] || healthy=false
[[ "$connection_continuity" == true ]] || healthy=false
(( reliability_failure_count == 0 )) || healthy=false
(( maximum_sample_gap_milliseconds <= 16000 )) || healthy=false
(( minimum_wall_clock_gap_seconds >= 0 )) || healthy=false
(( maximum_wall_clock_gap_seconds <= 16 )) || healthy=false

jq -s -e \
  --argjson healthy "$healthy" \
  --argjson connectionContinuity "$connection_continuity" \
  --argjson secondsSinceLastRecord "$seconds_since_last_record" \
  --argjson maximumSampleGapMilliseconds "$maximum_sample_gap_milliseconds" \
  --argjson minimumWallClockGapSeconds "$minimum_wall_clock_gap_seconds" \
  --argjson maximumWallClockGapSeconds "$maximum_wall_clock_gap_seconds" \
  --arg lastPhase "$last_phase" '
  [.[] | select(.telemetry != null)] as $samples |
  $samples[-1] as $last |
  {running:true, healthy:$healthy, connectionContinuity:$connectionContinuity,
   pid:'"$pid"', report:input_filename,
   lastPhase:$lastPhase, secondsSinceLastRecord:$secondsSinceLastRecord,
   maximumSampleGapMilliseconds:$maximumSampleGapMilliseconds,
   minimumWallClockGapSeconds:$minimumWallClockGapSeconds,
   maximumWallClockGapSeconds:$maximumWallClockGapSeconds,
   elapsedSeconds:($last.elapsedMilliseconds / 1000 | floor),
   samples:($samples | length), firmwareVersion:$last.telemetry.firmwareVersion,
   minimumFramesPerSecond:($samples | map(.telemetry.framesPerSecond) | min),
   minimumFreeHeapBytes:($samples | map(.telemetry.minimumFreeHeapBytes) | min),
   maximumInvalidFrameCount:($samples | map(.telemetry.invalidFrameCount) | max),
   maximumTouchReadErrorCount:($samples | map(.telemetry.touchReadErrorCount // 0) | max),
   maximumHandshakeCount:($samples | map(.telemetry.handshakeCount) | max),
   resetReasons:($samples | map(.telemetry.resetReason) | unique),
   touchCount:$last.telemetry.touchCount,
   maximumTouchInterruptCount:($samples | map(.telemetry.touchInterruptCount // 0) | max),
   maximumTouchPollAttemptCount:($samples | map(.telemetry.touchPollAttemptCount // 0) | max),
   maximumTouchPollTouchCount:($samples | map(.telemetry.touchPollTouchCount // 0) | max),
   touchControllerPresentEverySample:all($samples[]; .telemetry.touchControllerPresent == true),
   maximumTouchLatencyMs:($samples | map(.telemetry.maximumTouchLatencyMs) | max),
   reliabilityFailures:([.[].reliabilityFailures[]] | unique)}
' "$report"

[[ "$healthy" == true ]] || exit 1
