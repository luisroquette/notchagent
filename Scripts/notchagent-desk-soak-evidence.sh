#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

report="${1:-}"
duration_seconds="${2:-86400}"
[[ -f "$report" && ! -L "$report" && "$duration_seconds" =~ '^[1-9][0-9]*$' ]] || {
    echo "Usage: $0 soak-report.jsonl [duration-seconds]" >&2
    exit 2
}

app_bundle="${NOTCHAGENT_DESK_SOAK_APP:-dist/NotchAgent.app}"
[[ "$app_bundle" == /* || "$app_bundle" == "dist/NotchAgent.app" ]] || {
    echo "INVALID: NOTCHAGENT_DESK_SOAK_APP must be an absolute app path." >&2
    exit 2
}
release_manifest="firmware/notchagent_desk/release/manifest.json"
release_contract="docs/NOTCHAGENT_DESK_RELEASE.json"
[[ -f "$app_bundle/Contents/Info.plist" && -f "$release_manifest" && -f "$release_contract" ]] || {
    echo "INVALID: Beta 1 candidate metadata is missing." >&2
    exit 1
}
app_version=$(plutil -extract CFBundleShortVersionString raw "$app_bundle/Contents/Info.plist")
build_number=$(plutil -extract CFBundleVersion raw "$app_bundle/Contents/Info.plist")
firmware_version=$(jq -er '.firmwareVersion' "$release_manifest")
firmware_image_sha=$(jq -er '.imageSHA256' "$release_manifest")
firmware_source_sha=$(jq -er '.sourceSHA256' "$release_manifest")
jq -e --arg appVersion "$app_version" --arg buildNumber "$build_number" \
  --arg firmwareVersion "$firmware_version" '
  .appVersion == $appVersion and .buildNumber == $buildNumber and
  .firmwareVersion == $firmwareVersion and .protocolVersion == "1.1"
' "$release_contract" >/dev/null || {
    echo "INVALID: app, firmware, and release contract identify different candidates." >&2
    exit 1
}

expected_samples=$((duration_seconds / 10))
(( expected_samples >= 1 )) || expected_samples=1
report_sha=$(shasum -a 256 "$report" | awk '{print $1}')
source_report="$report"
[[ "$report" != "$PWD/"* ]] || source_report="${report#$PWD/}"
jq -s -e --argjson expected "$expected_samples" --argjson duration "$duration_seconds" \
  --arg firmwareVersion "$firmware_version" '
  [.[] | select(.telemetry != null)] as $samples |
  ($samples | map(.capturedAt | fromdateiso8601)) as $wallTimes |
  ($samples[0].elapsedMilliseconds // -1) as $first |
  ($samples[-1].elapsedMilliseconds // -1) as $last |
  ([range(1; $samples|length) as $index |
    $samples[$index].elapsedMilliseconds - $samples[$index - 1].elapsedMilliseconds] | max // 0) as $maxGap |
  ([range(1; $wallTimes|length) as $index |
    $wallTimes[$index] - $wallTimes[$index - 1]] | min // 0) as $minimumWallGap |
  ([range(1; $wallTimes|length) as $index |
    $wallTimes[$index] - $wallTimes[$index - 1]] | max // 0) as $maximumWallGap |
  ($samples | length) >= $expected and $first >= 0 and $first <= 10000 and
  $last >= (($duration * 1000) - 16000) and $maxGap <= 16000 and
  ($wallTimes[-1] - $wallTimes[0]) >= ($duration - 10) and
  $minimumWallGap >= 0 and $maximumWallGap <= 16 and
  all(.[] | select(.elapsedMilliseconds >= $first and .elapsedMilliseconds <= $last);
    .phase == "connected") and
  all($samples[];
    .firmwareVersion == $firmwareVersion and .protocolMajor == 1 and .protocolMinor == 1 and
    .telemetry.firmwareVersion == $firmwareVersion and .telemetry.framesPerSecond >= 7 and
    .telemetry.minimumFreeHeapBytes >= 122880 and .telemetry.invalidFrameCount == 0 and
    (.telemetry.touchReadErrorCount // 0) == 0 and .telemetry.touchControllerPresent == true and
    (.reliabilityFailures | length) == 0)
' "$report" >/dev/null || {
    echo "INVALID: soak source is incomplete, discontinuous, or unhealthy." >&2
    exit 1
}

jq -s \
  --argjson durationSeconds "$duration_seconds" \
  --arg sourceReport "$source_report" \
  --arg reportSHA256 "$report_sha" \
  --arg appVersion "$app_version" \
  --arg buildNumber "$build_number" \
  --arg firmwareImageSHA256 "$firmware_image_sha" \
  --arg firmwareSourceSHA256 "$firmware_source_sha" '
  [.[] | select(.telemetry != null)] as $samples |
  ($samples | map(.capturedAt | fromdateiso8601)) as $wallTimes |
  ([range(1; $samples|length) as $index |
    $samples[$index].elapsedMilliseconds - $samples[$index - 1].elapsedMilliseconds] | max // 0) as $maxGap |
  ([range(1; $wallTimes|length) as $index |
    $wallTimes[$index] - $wallTimes[$index - 1]] | max // 0) as $maximumWallGap |
  {schemaVersion:4,durationSeconds:$durationSeconds,samples:($samples|length),
   gate:"app-desk-soak",firmwareVersion:$samples[-1].telemetry.firmwareVersion,
   appVersion:$appVersion,buildNumber:$buildNumber,
   firmwareImageSHA256:$firmwareImageSHA256,firmwareSourceSHA256:$firmwareSourceSHA256,
   firstConnectionMilliseconds:$samples[0].elapsedMilliseconds,
   maximumSampleGapMilliseconds:$maxGap,connectionContinuity:true,
   firstCapturedAt:$samples[0].capturedAt,lastCapturedAt:$samples[-1].capturedAt,
   wallClockDurationSeconds:($wallTimes[-1] - $wallTimes[0]),
   maximumWallClockGapSeconds:$maximumWallGap,
   minimumFramesPerSecond:($samples|map(.telemetry.framesPerSecond)|min),
   minimumFreeHeapBytes:($samples|map(.telemetry.minimumFreeHeapBytes)|min),
   maximumInvalidFrameCount:($samples|map(.telemetry.invalidFrameCount)|max),
   maximumTouchReadErrorCount:($samples|map(.telemetry.touchReadErrorCount // 0)|max),
   sourceReport:$sourceReport,reportSHA256:$reportSHA256,result:"pass"}
' "$report"
