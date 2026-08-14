#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

report="${1:-}"
expected_reset_reason="${2:-usb}"
[[ -s "$report" ]] || {
    echo "Usage: $0 telemetry-report.jsonl [usb|power_on]" >&2
    exit 2
}
[[ "$expected_reset_reason" == "usb" || "$expected_reset_reason" == "power_on" ]] || {
    echo "Usage: $0 telemetry-report.jsonl [usb|power_on]" >&2
    exit 2
}

summary=$(jq -s -c '
  [.[] | select(.telemetry != null) | .telemetry] as $samples |
  {sampleCount:($samples | length),
   firmwareVersion:([$samples[].firmwareVersion] | unique | if length == 1 then .[0] else "mixed" end),
   minimumFramesPerSecond:($samples | map(.framesPerSecond) | min),
   minimumFreeHeapBytes:($samples | map(.minimumFreeHeapBytes) | min),
   maximumInvalidFrameCount:($samples | map(.invalidFrameCount) | max),
   maximumTouchReadErrorCount:($samples | map(.touchReadErrorCount // 0) | max),
   touchControllerPresentEverySample:all($samples[]; .touchControllerPresent == true),
   resetReasons:([$samples[].resetReason] | unique)}
' "$report")

jq -e --arg expectedResetReason "$expected_reset_reason" '
  .sampleCount >= 2 and .firmwareVersion == "0.6.16" and
  .minimumFramesPerSecond >= 7 and .minimumFreeHeapBytes >= 122880 and
  .maximumInvalidFrameCount == 0 and .maximumTouchReadErrorCount == 0 and
  .touchControllerPresentEverySample == true and
  (.resetReasons | index($expectedResetReason)) != null
' <<<"$summary" >/dev/null || {
    echo "FAIL: telemetry evidence does not satisfy the Beta 1 hardware contract." >&2
    exit 1
}

print -r -- "$summary"
