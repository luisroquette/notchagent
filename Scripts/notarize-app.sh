#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-dist/NotchAgent.app}"
profile="${NOTCHAGENT_NOTARY_PROFILE:-}"
evidence="${NOTCHAGENT_NOTARY_EVIDENCE:-docs/evidence/notchagent-desk-beta1-notarization.json}"
release_contract="docs/NOTCHAGENT_DESK_RELEASE.json"
expected_version=$(jq -er '.appVersion' "$release_contract")
expected_build=$(jq -er '.buildNumber' "$release_contract")
asset="${NOTCHAGENT_RELEASE_ASSET:-dist/NotchAgent-Desk-Beta1-${expected_version}.zip}"
[[ -d "$app" && -x "$app/Contents/MacOS/NotchAgent" ]] || {
    echo "Usage: NOTCHAGENT_NOTARY_PROFILE=<keychain-profile> $0 [app-path]" >&2
    exit 2
}
[[ -n "$profile" ]] || {
    echo "NOT READY: set NOTCHAGENT_NOTARY_PROFILE to an existing notarytool Keychain profile." >&2
    exit 2
}
[[ "$evidence" == *.json ]] || {
    echo "NOT READY: NOTCHAGENT_NOTARY_EVIDENCE must point to a JSON file." >&2
    exit 2
}
[[ "$asset" == *.zip ]] || {
    echo "NOT READY: NOTCHAGENT_RELEASE_ASSET must point to a ZIP file." >&2
    exit 2
}
[[ ! -e "$evidence" && ! -e "$asset" ]] || {
    echo "NOT READY: notarization evidence or release asset already exists; preserve it and choose new explicit paths." >&2
    exit 2
}

authority=$(codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)
[[ "$authority" == "Developer ID Application:"* ]] || {
    echo "NOT READY: app must be signed with Developer ID Application; found ${authority:-none}." >&2
    exit 1
}
codesign --verify --deep --strict --verbose=2 "$app"
signature_details=$(codesign -d --verbose=4 "$app" 2>&1)
print -r -- "$signature_details" | grep -q '^Identifier=br.com.lfrprojects.notchagent$' || {
    echo "NOT READY: app bundle identifier does not match the release contract." >&2
    exit 1
}
print -r -- "$signature_details" | grep -q 'flags=.*runtime' || {
    echo "NOT READY: hardened runtime is missing." >&2
    exit 1
}

notary_dir=$(mktemp -d -t notchagent-notary)
[[ -n "$notary_dir" && "$notary_dir" == /var/folders/*/T/* ]] || exit 1
asset_tmp=""
evidence_tmp=""
cleanup() {
    [[ -n "$notary_dir" && -d "$notary_dir" && "$notary_dir" == /var/folders/*/T/* ]] || return 0
    rm -r -- "$notary_dir"
    [[ -z "$asset_tmp" || ! -f "$asset_tmp" ]] || rm -- "$asset_tmp"
    [[ -z "$evidence_tmp" || ! -f "$evidence_tmp" ]] || rm -- "$evidence_tmp"
}
trap cleanup EXIT
archive="$notary_dir/NotchAgent.zip"
notary_result="$notary_dir/notary-result.json"
ditto -c -k --keepParent "$app" "$archive"

xcrun notarytool submit "$archive" --keychain-profile "$profile" --wait \
    --output-format json > "$notary_result"
[[ "$(jq -r '.status // ""' "$notary_result")" == "Accepted" ]] || {
    echo "FAIL: Apple notarization did not return Accepted." >&2
    exit 1
}
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
info_plist="$app/Contents/Info.plist"
bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
[[ "$app_version" == "$expected_version" && "$build_number" == "$expected_build" ]] || {
    echo "NOT READY: app version/build does not match the Beta 1 release contract." >&2
    exit 1
}
executable_sha=$(shasum -a 256 "$app/Contents/MacOS/NotchAgent" | awk '{print $1}')
evidence_dir="${evidence:h}"
asset_dir="${asset:h}"
mkdir -p "$evidence_dir"
mkdir -p "$asset_dir"
asset_tmp=$(mktemp "$asset_dir/.notchagent-release.XXXXXX")
ditto -c -k --keepParent "$app" "$asset_tmp"
asset_sha=$(shasum -a 256 "$asset_tmp" | awk '{print $1}')
evidence_tmp=$(mktemp "$evidence_dir/.notarization.XXXXXX")
jq -n \
    --arg completedAt "$(date -u +%FT%TZ)" \
    --arg bundleIdentifier "$bundle_identifier" \
    --arg appVersion "$app_version" \
    --arg buildNumber "$build_number" \
    --arg executableSHA256 "$executable_sha" \
    --arg releaseAssetFilename "${asset:t}" \
    --arg releaseAssetSHA256 "$asset_sha" \
    '{schemaVersion:2, gate:"developer-id-notarization", completedAt:$completedAt,
      bundleIdentifier:$bundleIdentifier, appVersion:$appVersion, buildNumber:$buildNumber,
      signatureKind:"Developer ID Application", hardenedRuntime:true,
      notarizationStatus:"Accepted", stapleValidated:true, gatekeeperAccepted:true,
      executableSHA256:$executableSHA256, releaseAssetFilename:$releaseAssetFilename,
      releaseAssetSHA256:$releaseAssetSHA256, result:"pass"}' > "$evidence_tmp"
mv -- "$asset_tmp" "$asset"
mv -- "$evidence_tmp" "$evidence"
echo "PASS: Developer ID signature, notarization ticket, staple, and Gatekeeper assessment validated."
echo "Release asset: $asset ($asset_sha)"
echo "Evidence: $evidence"
