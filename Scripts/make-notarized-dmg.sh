#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-dist/NotchAgent.app}"
profile="${NOTCHAGENT_NOTARY_PROFILE:-}"
identity="${NOTCHAGENT_SIGN_IDENTITY:-}"
version=$(jq -er '.appVersion' docs/NOTCHAGENT_DESK_RELEASE.json)
build=$(jq -er '.buildNumber' docs/NOTCHAGENT_DESK_RELEASE.json)
output="${NOTCHAGENT_DMG_OUTPUT:-dist/NotchAgent-Desk-Beta1-${version}.dmg}"
evidence="${NOTCHAGENT_DMG_EVIDENCE:-docs/evidence/notchagent-desk-beta1-dmg-notarization.json}"

[[ -d "$app" && -x "$app/Contents/MacOS/NotchAgent" ]] || {
    echo "NOT READY: signed NotchAgent.app not found at $app." >&2
    exit 2
}
[[ -n "$profile" ]] || {
    echo "NOT READY: set NOTCHAGENT_NOTARY_PROFILE." >&2
    exit 2
}
[[ -n "$identity" ]] || {
    echo "NOT READY: set NOTCHAGENT_SIGN_IDENTITY." >&2
    exit 2
}
[[ "$output" == *.dmg && "$evidence" == *.json ]] || {
    echo "NOT READY: output must be .dmg and evidence must be .json." >&2
    exit 2
}
[[ ! -e "$output" && ! -e "$evidence" ]] || {
    echo "NOT READY: preserve the existing DMG/evidence and choose new paths." >&2
    exit 2
}

app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
app_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ "$app_version" == "$version" && "$app_build" == "$build" ]] || {
    echo "NOT READY: app version/build differs from the release contract." >&2
    exit 1
}
codesign --verify --deep --strict --verbose=2 "$app"
xcrun stapler validate "$app"

work_dir=$(mktemp -d -t notchagent-dmg)
[[ -n "$work_dir" && -d "$work_dir" && "$work_dir" == /var/folders/*/T/* ]] || exit 1
cleanup() {
    [[ -n "$work_dir" && -d "$work_dir" && "$work_dir" == /var/folders/*/T/* ]] || return 0
    rm -r -- "$work_dir"
}
trap cleanup EXIT

stage="$work_dir/NotchAgent Desk"
mkdir -p "$stage"
ditto "$app" "$stage/NotchAgent.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/Comece aqui.webloc" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>URL</key><string>https://cfgauss.com.br/notchagent/instalar</string></dict></plist>
PLIST
plutil -lint "$stage/Comece aqui.webloc" >/dev/null

mkdir -p "${output:h}" "${evidence:h}"
temporary_dmg="$work_dir/NotchAgent-Desk-Beta1-${version}.dmg"
hdiutil create -quiet -volname "NotchAgent Desk" -srcfolder "$stage" -format UDZO "$temporary_dmg"
codesign --force --sign "$identity" --timestamp "$temporary_dmg"

result="$work_dir/notary-result.json"
xcrun notarytool submit "$temporary_dmg" --keychain-profile "$profile" --wait --output-format json > "$result"
[[ "$(jq -r '.status // ""' "$result")" == "Accepted" ]] || {
    echo "FAIL: Apple did not accept the DMG notarization." >&2
    exit 1
}
xcrun stapler staple "$temporary_dmg"
xcrun stapler validate "$temporary_dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$temporary_dmg"

dmg_sha=$(shasum -a 256 "$temporary_dmg" | awk '{print $1}')
submission_id=$(jq -r '.id' "$result")
mv "$temporary_dmg" "$output"
jq -n \
    --arg completedAt "$(date -u +%FT%TZ)" \
    --arg appVersion "$version" \
    --arg buildNumber "$build" \
    --arg submissionID "$submission_id" \
    --arg filename "${output:t}" \
    --arg sha256 "$dmg_sha" \
    '{schemaVersion:1,gate:"notarized-dmg",result:"pass",completedAt:$completedAt,
      appVersion:$appVersion,buildNumber:$buildNumber,notarizationStatus:"Accepted",
      stapleValidated:true,gatekeeperAccepted:true,submissionID:$submissionID,
      filename:$filename,sha256:$sha256}' > "$evidence"

echo "PASS: notarized DMG validated at $output ($dmg_sha)"
echo "Evidence: $evidence"
