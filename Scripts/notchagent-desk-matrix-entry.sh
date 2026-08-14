#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

report="${1:-}"
mac_class="${2:-}"
unit_alias="${3:-}"
connection_class="${4:-}"
connection_alias="${5:-}"
[[ -f "$report" ]] || {
    echo "Usage: $0 reconnect-report.json mac-class unit-alias direct|dock|hub connection-alias" >&2
    exit 2
}
[[ "$mac_class" =~ '^[a-z0-9][a-z0-9-]{2,47}$' ]] || { echo "INVALID: mac class alias." >&2; exit 2; }
[[ "$unit_alias" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' ]] || { echo "INVALID: unit alias." >&2; exit 2; }
[[ "$connection_class" == "direct" || "$connection_class" == "dock" || "$connection_class" == "hub" ]] || {
    echo "INVALID: connection class." >&2
    exit 2
}
[[ "$connection_alias" =~ '^[A-Z0-9][A-Z0-9-]{0,31}$' ]] || { echo "INVALID: connection alias." >&2; exit 2; }
if [[ "$connection_class" == "direct" ]]; then
    [[ "$connection_alias" == "DIRECT" ]] || { echo "INVALID: direct connection alias must be DIRECT." >&2; exit 2; }
else
    [[ "$connection_alias" != "DIRECT" ]] || { echo "INVALID: dock/hub must use a non-DIRECT alias." >&2; exit 2; }
fi

macos_major="${NOTCHAGENT_DESK_MATRIX_MACOS_MAJOR:-$(sw_vers -productVersion | cut -d. -f1)}"
[[ "$macos_major" =~ '^[0-9]+$' && "$macos_major" -ge 14 ]] || {
    echo "INVALID: macOS 14 or newer is required." >&2
    exit 2
}

summary=$(Scripts/notchagent-desk-reconnect-evidence.sh "$report" 10)
jq -e '.result == "pass" and .cycles >= 10 and .firmwareVersion == "0.6.16"' <<<"$summary" >/dev/null || {
    echo "INVALID: reconnect evidence does not satisfy the matrix entry." >&2
    exit 1
}

jq -n \
  --arg macClass "$mac_class" \
  --arg unitAlias "$unit_alias" \
  --arg connectionClass "$connection_class" \
  --arg connectionAlias "$connection_alias" \
  --argjson macOSMajor "$macos_major" \
  --argjson summary "$summary" '
  {macClass:$macClass, macOSMajor:$macOSMajor, unitAlias:$unitAlias,
   connectionClass:$connectionClass, connectionAlias:$connectionAlias,
   firmwareVersion:$summary.firmwareVersion,
   firmwareImageSHA256:$summary.firmwareImageSHA256,
   firmwareSourceSHA256:$summary.firmwareSourceSHA256,
   sourceReport:$summary.sourceReport,
   sourceReportSHA256:$summary.sourceReportSHA256,
   attempts:$summary.cycles, successes:$summary.cycles,
   maximumConnectionSeconds:($summary.maximumReconnectMilliseconds / 1000),
   minimumFramesPerSecond:$summary.minimumFramesPerSecond,
   minimumFreeHeapBytes:$summary.minimumFreeHeapBytes,
   maximumInvalidFrameCount:$summary.maximumInvalidFrameCount,
   maximumTouchReadErrorCount:$summary.maximumTouchReadErrorCount,
   touchControllerPresentEveryAttempt:$summary.touchControllerPresentEveryCycle}
'
