#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

report="${1:-}"
output_dir="${2:-docs/evidence}"
app="dist/NotchAgent.app"
release="firmware/notchagent_desk/release/manifest.json"
contract="docs/NOTCHAGENT_DESK_RELEASE.json"
[[ -f "$report" && -d "$app" && -f "$release" && -f "$contract" ]] || {
    echo "Usage: $0 live-soak-report.jsonl [evidence-directory]" >&2
    exit 2
}
mkdir -p "$output_dir"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
snapshot="$output_dir/notchagent-desk-beta1-smoke-source-${stamp}.jsonl"
smoke="$output_dir/notchagent-desk-beta1-final-smoke-${stamp}.json"
identity="$output_dir/notchagent-desk-beta1-identity-${stamp}.json"
for target in "$snapshot" "$smoke" "$identity"; do
    [[ ! -e "$target" ]] || { echo "FAIL: evidence collision preserved: $target" >&2; exit 1; }
done

snapshot_tmp=$(mktemp "$output_dir/.smoke-source.XXXXXX")
smoke_tmp=$(mktemp "$output_dir/.smoke.XXXXXX")
identity_tmp=$(mktemp "$output_dir/.identity.XXXXXX")
cleanup() {
    [[ ! -f "$snapshot_tmp" ]] || rm -- "$snapshot_tmp"
    [[ ! -f "$smoke_tmp" ]] || rm -- "$smoke_tmp"
    [[ ! -f "$identity_tmp" ]] || rm -- "$identity_tmp"
}
trap cleanup EXIT
jq -c . "$report" > "$snapshot_tmp"

jq -s -e '
  [.[] | select(.telemetry != null)] as $samples |
  ($samples[0].elapsedMilliseconds // -1) as $first |
  ($samples[-1].elapsedMilliseconds // -1) as $last |
  ([range(1; $samples|length) as $i |
    $samples[$i].elapsedMilliseconds - $samples[$i - 1].elapsedMilliseconds] | max // 0) as $gap |
  ($samples | length) >= 10 and $first >= 0 and ($last - $first) >= 45000 and $gap <= 10000 and
  all(.[] | select(.elapsedMilliseconds >= $first and .elapsedMilliseconds <= $last);
    .phase == "connected") and
  all($samples[];
    .firmwareVersion == "0.6.16" and .protocolMajor == 1 and .protocolMinor == 1 and
    .telemetry.firmwareVersion == "0.6.16" and .telemetry.framesPerSecond >= 7 and
    .telemetry.minimumFreeHeapBytes >= 122880 and .telemetry.invalidFrameCount == 0 and
    (.telemetry.touchReadErrorCount // 0) == 0 and .telemetry.touchControllerPresent == true and
    (.reliabilityFailures | length) == 0)
' "$snapshot_tmp" >/dev/null || {
    echo "NOT READY: report lacks 45 seconds of continuous healthy Beta 1 telemetry." >&2
    exit 1
}

app_version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
build_number=$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")
bundle_identifier=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
firmware_version=$(jq -r '.firmwareVersion' "$release")
image_sha=$(jq -r '.imageSHA256' "$release")
source_sha=$(jq -r '.sourceSHA256' "$release")
jq -e --arg appVersion "$app_version" --arg buildNumber "$build_number" \
  --arg firmwareVersion "$firmware_version" '
  .appVersion == $appVersion and .buildNumber == $buildNumber and
  .firmwareVersion == $firmwareVersion and .protocolVersion == "1.1"
' "$contract" >/dev/null || { echo "FAIL: app and firmware do not match release contract." >&2; exit 1; }
[[ "$bundle_identifier" == "br.com.lfrprojects.notchagent" ]] || exit 1
codesign --verify --deep --strict "$app"
authority=$(codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)
signature_kind="${authority%%:*}"
[[ "$signature_kind" == "Apple Development" || "$signature_kind" == "Developer ID Application" ]] || {
    echo "FAIL: smoke app lacks an Apple signing identity." >&2
    exit 1
}
report_sha=$(shasum -a 256 "$snapshot_tmp" | awk '{print $1}')

jq -s --arg appVersion "$app_version" --arg buildNumber "$build_number" \
  --arg signatureKind "$signature_kind" --arg firmwareVersion "$firmware_version" \
  --arg imageSHA "$image_sha" --arg sourceSHA "$source_sha" \
  --arg sourceReport "$snapshot" --arg reportSHA "$report_sha" '
  [.[] | select(.telemetry != null)] as $samples |
  ($samples[0].elapsedMilliseconds) as $first |
  ($samples[-1].elapsedMilliseconds) as $last |
  ([range(1; $samples|length) as $i |
    $samples[$i].elapsedMilliseconds - $samples[$i - 1].elapsedMilliseconds] | max // 0) as $gap |
  {schemaVersion:2,gate:"final-app-physical-smoke",result:"pass",
   capturedAt:$samples[-1].capturedAt,durationSeconds:(($last - $first) / 1000 | floor),
   appVersion:$appVersion,buildNumber:$buildNumber,signatureKind:$signatureKind,
   firmwareVersion:$firmwareVersion,firmwareImageSHA256:$imageSHA,
   firmwareSourceSHA256:$sourceSHA,protocolVersion:"1.1",connectionContinuity:true,
   firstConnectionMilliseconds:$first,maximumSampleGapMilliseconds:$gap,
   minimumFramesPerSecond:($samples|map(.telemetry.framesPerSecond)|min),
   minimumFreeHeapBytes:($samples|map(.telemetry.minimumFreeHeapBytes)|min),
   maximumInvalidFrameCount:($samples|map(.telemetry.invalidFrameCount)|max),
   maximumTouchReadErrorCount:($samples|map(.telemetry.touchReadErrorCount // 0)|max),
   touchControllerPresent:all($samples[];.telemetry.touchControllerPresent == true),
   touchCount:($samples|map(.telemetry.touchCount // 0)|max),
   sourceReport:$sourceReport,reportSHA256:$reportSHA}
' "$snapshot_tmp" > "$smoke_tmp"

jq -s --arg firmwareVersion "$firmware_version" --arg imageSHA "$image_sha" \
  --arg sourceSHA "$source_sha" --arg sourceReport "$snapshot" --arg reportSHA "$report_sha" '
  [.[] | select(.telemetry != null)] as $samples |
  {schemaVersion:2,gate:"firmware-protocol-visible",result:"pass",
   capturedAt:$samples[-1].capturedAt,firmwareVersion:$firmwareVersion,
   protocolVersion:"1.1",firmwareImageSHA256:$imageSHA,firmwareSourceSHA256:$sourceSHA,
   telemetryFirmwareVersion:$samples[-1].telemetry.firmwareVersion,
   telemetryPresent:true,sourceReport:$sourceReport,sourceReportSHA256:$reportSHA}
' "$snapshot_tmp" > "$identity_tmp"

mv -- "$snapshot_tmp" "$snapshot"
mv -- "$smoke_tmp" "$smoke"
mv -- "$identity_tmp" "$identity"
echo "PASS: final-app smoke and firmware identity evidence captured."
echo "Smoke: $smoke"
echo "Identity: $identity"
echo "Source: $snapshot"
