#!/bin/zsh
set -euo pipefail

report="${1:-}"
target="${2:-100}"
script_dir="${0:A:h}"
release_manifest="${NOTCHAGENT_DESK_RELEASE_MANIFEST:-$script_dir/../firmware/notchagent_desk/release/manifest.json}"
[[ -f "$report" && "$target" =~ '^[1-9][0-9]*$' ]] || {
    echo "Usage: $0 reconnect-report.json [minimum-cycles]" >&2
    exit 2
}
[[ -f "$release_manifest" ]] || {
    echo "INVALID: firmware release manifest is missing: $release_manifest" >&2
    exit 1
}
jq -e '
  .schemaVersion == 2 and
  (.firmwareVersion | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.imageSHA256 | test("^[0-9a-f]{64}$")) and
  (.sourceSHA256 | test("^[0-9a-f]{64}$"))
' "$release_manifest" >/dev/null || {
    echo "INVALID: firmware release manifest is malformed." >&2
    exit 1
}
firmware_version=$(jq -r '.firmwareVersion' "$release_manifest")
firmware_image_sha=$(jq -r '.imageSHA256' "$release_manifest")
firmware_source_sha=$(jq -r '.sourceSHA256' "$release_manifest")

filename="${report:t}"
stamp="${filename#reconnect-}"
stamp="${stamp%.json}"
[[ "$stamp" =~ '^[0-9]{8}T[0-9]{6}Z$' ]] || {
    echo "INVALID: reconnect report filename has no UTC timestamp." >&2
    exit 1
}
executed_at="${stamp[1,4]}-${stamp[5,6]}-${stamp[7,8]}T${stamp[10,11]}:${stamp[12,13]}:${stamp[14,15]}Z"
sha=$(shasum -a 256 "$report" | awk '{print $1}')

jq -e --argjson target "$target" --arg firmwareVersion "$firmware_version" '
  type == "array" and length >= $target and
  ([.[].cycle] == [range(1; length + 1)]) and
  all(.[];
    (.reconnectMilliseconds | type) == "number" and .reconnectMilliseconds > 0 and
    .reconnectMilliseconds <= 15000 and
    (.resetMilliseconds | type) == "number" and .resetMilliseconds > 0 and
    (.telemetryMilliseconds | type) == "number" and .telemetryMilliseconds > 0 and
    .reconnectMilliseconds == (.resetMilliseconds + .telemetryMilliseconds) and
    .telemetry.firmwareVersion == $firmwareVersion and
    (.telemetry.uptimeSeconds | type) == "number" and .telemetry.uptimeSeconds > 0 and
    .telemetry.uptimeSeconds <= 30 and .telemetry.resetReason == "usb" and
    (.telemetry.handshakeCount | type) == "number" and .telemetry.handshakeCount >= 1 and
    (.telemetry.touchPollAttemptCount | type) == "number" and .telemetry.touchPollAttemptCount > 0 and
    .telemetry.framesPerSecond >= 7 and .telemetry.minimumFreeHeapBytes >= 122880 and
    .telemetry.invalidFrameCount == 0 and (.telemetry.touchReadErrorCount // 0) == 0 and
    .telemetry.touchControllerPresent == true)
' "$report" >/dev/null || {
    echo "INVALID: reconnect samples are incomplete, out of order, or unhealthy." >&2
    exit 1
}

jq --arg executedAt "$executed_at" \
   --arg sourceReport "$report" \
   --arg sourceReportSHA256 "$sha" \
   --arg firmwareImageSHA256 "$firmware_image_sha" \
   --arg firmwareSourceSHA256 "$firmware_source_sha" '
  {schemaVersion:3, gate:"physical-reset-usb-reconnect", executedAt:$executedAt,
   firmwareVersion:.[-1].telemetry.firmwareVersion, cycles:length,
   firmwareImageSHA256:$firmwareImageSHA256,
   firmwareSourceSHA256:$firmwareSourceSHA256,
   durationSeconds:((map(.reconnectMilliseconds) | add) / 1000),
   maximumReconnectMilliseconds:(map(.reconnectMilliseconds) | max),
   maximumResetMilliseconds:(map(.resetMilliseconds // 0) | max),
   maximumTelemetryMilliseconds:(map(.telemetryMilliseconds // 0) | max),
   maximumBootUptimeSeconds:(map(.telemetry.uptimeSeconds) | max),
   minimumHandshakeCountPerCycle:(map(.telemetry.handshakeCount) | min),
   minimumFramesPerSecond:(map(.telemetry.framesPerSecond) | min),
   minimumFreeHeapBytes:(map(.telemetry.minimumFreeHeapBytes) | min),
   maximumInvalidFrameCount:(map(.telemetry.invalidFrameCount) | max),
   maximumTouchReadErrorCount:(map(.telemetry.touchReadErrorCount // 0) | max),
   touchControllerPresentEveryCycle:all(.[]; .telemetry.touchControllerPresent == true),
   minimumTouchPollAttemptsPerCycle:(map(.telemetry.touchPollAttemptCount // 0) | min),
   resetReasons:([.[].telemetry.resetReason] | unique), result:"pass",
   sourceReport:$sourceReport,sourceReportSHA256:$sourceReportSHA256}
' "$report"
