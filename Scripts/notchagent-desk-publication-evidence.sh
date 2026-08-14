#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

notarization="${1:-docs/evidence/notchagent-desk-beta1-notarization.json}"
output="${2:-docs/evidence/notchagent-desk-beta1-onboarding.json}"
release_contract="docs/NOTCHAGENT_DESK_RELEASE.json"
qr_file="docs/img/notchagent-desk-onboarding-qr.svg"
url="https://github.com/luisroquette/notchagent/blob/master/docs/NOTCHAGENT_DESK_ONBOARDING.md"
version=$(jq -er '.appVersion' "$release_contract")
build_number=$(jq -er '.buildNumber' "$release_contract")
asset_url="https://github.com/luisroquette/notchagent/releases/download/v${version}/NotchAgent-Desk-Beta1-${version}.zip"

[[ -f "$notarization" && ! -e "$output" ]] || {
    echo "NOT READY: notarization evidence must exist and onboarding evidence must not already exist." >&2
    exit 2
}
jq -e --arg version "$version" '
  .schemaVersion == 2 and .gate == "developer-id-notarization" and .result == "pass" and
  .appVersion == $version and .notarizationStatus == "Accepted" and
  .stapleValidated == true and .gatekeeperAccepted == true and
  (.releaseAssetSHA256 | test("^[0-9a-f]{64}$"))
' "$notarization" >/dev/null || {
    echo "INVALID: notarization evidence is not the accepted Beta 1 release." >&2
    exit 1
}
Scripts/notchagent-desk-onboarding-qr-gate.swift "$qr_file" \
  docs/NOTCHAGENT_DESK_ONBOARDING_URL.txt >/dev/null

work=$(mktemp -d -t notchagent-publication)
[[ -n "$work" && "$work" == /var/folders/*/T/* ]] || exit 1
tmp=""
cleanup() {
    if [[ -n "$work" && -d "$work" && "$work" == /var/folders/*/T/* ]]; then
        rm -r -- "$work"
    fi
    [[ -z "$tmp" || ! -f "$tmp" ]] || rm -- "$tmp"
}
trap cleanup EXIT

published_commit=$(git ls-remote https://github.com/luisroquette/notchagent.git refs/heads/master | awk 'NR == 1 {print $1}')
print -r -- "$published_commit" | grep -Eq '^[0-9a-f]{40}$' || {
    echo "FAIL: public master commit could not be resolved." >&2
    exit 1
}
guide_url="https://raw.githubusercontent.com/luisroquette/notchagent/${published_commit}/docs/NOTCHAGENT_DESK_ONBOARDING.md"
curl --fail --silent --show-error --location --max-time 30 --max-filesize 1048576 \
  "$guide_url" --output "$work/onboarding.md"
curl --fail --silent --show-error --location --max-time 300 --max-filesize 104857600 \
  "$asset_url" --output "$work/NotchAgent.zip"
unzip -t "$work/NotchAgent.zip" >/dev/null
mkdir "$work/extracted"
ditto -x -k "$work/NotchAgent.zip" "$work/extracted"
downloaded_apps=("$work"/extracted/*.app(N))
(( ${#downloaded_apps} == 1 )) || {
    echo "FAIL: published ZIP must contain exactly one top-level app bundle." >&2
    exit 1
}
downloaded_app="${downloaded_apps[1]}"
downloaded_info="$downloaded_app/Contents/Info.plist"
downloaded_executable="$downloaded_app/Contents/MacOS/NotchAgent"
downloaded_firmware="$downloaded_app/Contents/Resources/DeskFirmware"
[[ -f "$downloaded_info" && -x "$downloaded_executable" && -d "$downloaded_firmware" ]] || {
    echo "FAIL: published app bundle is incomplete." >&2
    exit 1
}
codesign --verify --deep --strict --verbose=2 "$downloaded_app" >/dev/null 2>&1
signature_details=$(codesign -d --verbose=4 "$downloaded_app" 2>&1)
authority=$(print -r -- "$signature_details" | sed -n 's/^Authority=//p' | head -1)
[[ "$authority" == "Developer ID Application:"* ]] || {
    echo "FAIL: published app lacks a Developer ID Application signature." >&2
    exit 1
}
print -r -- "$signature_details" | grep -q '^Identifier=br.com.lfrprojects.notchagent$' || {
    echo "FAIL: published app bundle identifier is incorrect." >&2
    exit 1
}
print -r -- "$signature_details" | grep -q 'flags=.*runtime' || {
    echo "FAIL: published app lacks hardened runtime." >&2
    exit 1
}
xcrun stapler validate "$downloaded_app" >/dev/null
spctl --assess --type execute --verbose=2 "$downloaded_app" >/dev/null 2>&1
downloaded_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$downloaded_info")
downloaded_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$downloaded_info")
[[ "$downloaded_version" == "$version" && "$downloaded_build" == "$build_number" ]] || {
    echo "FAIL: published app version/build differs from the Beta 1 contract." >&2
    exit 1
}
firmware/notchagent_desk/verify-release.sh "$downloaded_firmware" >/dev/null
downloaded_executable_sha=$(shasum -a 256 "$downloaded_executable" | awk '{print $1}')
downloaded_firmware_manifest_sha=$(shasum -a 256 "$downloaded_firmware/manifest.json" | awk '{print $1}')
[[ "$downloaded_executable_sha" == "$(jq -r '.executableSHA256' "$notarization")" ]] || {
    echo "FAIL: published executable differs from notarization evidence." >&2
    exit 1
}

guide_sha=$(shasum -a 256 "$work/onboarding.md" | awk '{print $1}')
asset_sha=$(shasum -a 256 "$work/NotchAgent.zip" | awk '{print $1}')
expected_asset_sha=$(jq -r '.releaseAssetSHA256' "$notarization")
[[ "$asset_sha" == "$expected_asset_sha" ]] || {
    echo "FAIL: published release ZIP differs from the notarized asset." >&2
    exit 1
}

output_dir="${output:h}"
mkdir -p "$output_dir"
tmp=$(mktemp "$output_dir/.onboarding-publication.XXXXXX")
jq -n \
  --arg verifiedAt "$(date -u +%FT%TZ)" \
  --arg url "$url" \
  --arg qrFile "$qr_file" \
  --arg qrSHA256 "$(shasum -a 256 "$qr_file" | awk '{print $1}')" \
  --arg publishedCommitSHA "$published_commit" \
  --arg guideContentSHA256 "$guide_sha" \
  --arg releaseAssetURL "$asset_url" \
  --arg releaseAssetSHA256 "$asset_sha" \
  --arg notarizationEvidenceSHA256 "$(shasum -a 256 "$notarization" | awk '{print $1}')" \
  --arg downloadedExecutableSHA256 "$downloaded_executable_sha" \
  --arg downloadedFirmwareManifestSHA256 "$downloaded_firmware_manifest_sha" \
  '{schemaVersion:3,gate:"onboarding-qr",result:"pass",verifiedAt:$verifiedAt,
    verificationMethod:"live-download",url:$url,qrFile:$qrFile,qrSHA256:$qrSHA256,
    publishedCommitSHA:$publishedCommitSHA,guideHTTPStatus:200,
    guideContentSHA256:$guideContentSHA256,releaseAssetURL:$releaseAssetURL,
    releaseAssetSHA256:$releaseAssetSHA256,
    notarizationEvidenceSHA256:$notarizationEvidenceSHA256,
    downloadedExecutableSHA256:$downloadedExecutableSHA256,
    downloadedFirmwareManifestSHA256:$downloadedFirmwareManifestSHA256,
    artifactSignatureVerified:true,artifactStapleValidated:true,
    artifactGatekeeperAccepted:true,artifactFirmwareVerified:true,
    developerIDSigned:true,notarized:true}' > "$tmp"
mv -- "$tmp" "$output"
echo "PASS: public guide and release asset match notarization evidence."
echo "Evidence: $output"
