#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

test_root=$(mktemp -d "$PWD/.distribution-contract.XXXXXX")
[[ -n "$test_root" && -d "$test_root" && "$test_root" == "$PWD/.distribution-contract."* ]] || exit 1
cleanup() {
    [[ -n "$test_root" && -d "$test_root" && "$test_root" == "$PWD/.distribution-contract."* ]] || return 0
    rm -r -- "$test_root"
}
trap cleanup EXIT

jq -e '.pins[] | select(.identity == "sparkle") | .state.version == "2.9.4"' \
    Package.resolved >/dev/null || {
    echo "FAIL: Package.resolved must pin Sparkle 2.9.4." >&2
    exit 1
}

# The live appcast must announce the version in VERSION. If it diverges,
# every installed app is frozen on an old release and updates are dead.
live_feed=$(curl -fsSL --max-time 15 \
    'https://raw.githubusercontent.com/luisroquette/notchagent/master/appcast.xml' \
    2>/dev/null || echo '')
feed_version=$(printf '%s' "$live_feed" | grep -oE '<sparkle:shortVersionString>[^<]+' \
    | head -1 | sed 's/.*>//')
[[ -n "$feed_version" ]] || {
    echo "FAIL: live appcast unreachable — cannot verify the update channel." >&2
    exit 1
}
[[ "$feed_version" == "$(cat VERSION)" ]] || {
    echo "FAIL: live appcast announces $feed_version but VERSION is $(cat VERSION). Installed apps are frozen." >&2
    exit 1
}

plutil -lint Resources/DeskFirmwareEsptool.entitlements.plist >/dev/null
rg -q 'com\.apple\.security\.cs\.disable-library-validation' \
    Resources/DeskFirmwareEsptool.entitlements.plist || {
    echo "FAIL: Desk flasher entitlement is missing." >&2
    exit 1
}
rg -q 'ESPTOOL_SIGN_ARGS.*--entitlements' Scripts/make-app.sh || {
    echo "FAIL: Developer ID packaging does not apply the Desk flasher entitlement." >&2
    exit 1
}

set +e
missing_update_output=$(NOTCHAGENT_SIGN_IDENTITY='Developer ID Application: contract-test' \
    Scripts/make-app.sh 2>&1)
missing_update_result=$?
partial_update_output=$(NOTCHAGENT_UPDATE_FEED_URL='https://updates.example.invalid/appcast.xml' \
    Scripts/make-app.sh 2>&1)
partial_update_result=$?
appcast_output=$(Scripts/generate-update-appcast.sh "$test_root/missing.zip" \
    "$test_root/updates" 2>&1)
appcast_result=$?
set -e

[[ $missing_update_result -ne 0 &&
   "$missing_update_output" == 'NOT READY: Developer ID build requires NOTCHAGENT_UPDATE_FEED_URL with HTTPS.' ]] || {
    echo "FAIL: Developer ID build accepted missing update configuration." >&2
    exit 1
}
[[ $partial_update_result -ne 0 &&
   "$partial_update_output" == 'NOT READY: configure both a valid HTTPS update feed and Sparkle EdDSA public key.' ]] || {
    echo "FAIL: build accepted partial update configuration." >&2
    exit 1
}
[[ $appcast_result -eq 2 && "$appcast_output" == 'NOT READY: notarized release ZIP not found:'* ]] || {
    echo "FAIL: appcast generation accepted a missing notarized asset." >&2
    exit 1
}

fake_public_key='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
NOTCHAGENT_DIST_DIR="$test_root/dist" \
NOTCHAGENT_UPDATE_FEED_URL='https://updates.example.invalid/appcast.xml' \
NOTCHAGENT_UPDATE_PUBLIC_ED_KEY="$fake_public_key" \
Scripts/make-app.sh >/dev/null

app="$test_root/dist/NotchAgent.app"
info="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/NotchAgent"
framework="$app/Contents/Frameworks/Sparkle.framework"
[[ -x "$executable" && -d "$framework" ]] || {
    echo "FAIL: packaged app does not embed the executable and Sparkle framework." >&2
    exit 1
}
codesign --verify --deep --strict "$app"
otool -L "$executable" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle' || {
    echo "FAIL: packaged executable is not linked to embedded Sparkle." >&2
    exit 1
}
otool -l "$executable" | grep -q '@executable_path/../Frameworks' || {
    echo "FAIL: packaged executable cannot resolve its embedded frameworks." >&2
    exit 1
}
[[ "$(plutil -extract SUFeedURL raw -o - "$info")" == 'https://updates.example.invalid/appcast.xml' &&
   "$(plutil -extract SUPublicEDKey raw -o - "$info")" == "$fake_public_key" &&
   "$(plutil -extract SUEnableAutomaticChecks raw -o - "$info")" == 'true' &&
   "$(plutil -extract SUAutomaticallyUpdate raw -o - "$info")" == 'true' ]] || {
    echo "FAIL: packaged app does not contain the complete automatic-update contract." >&2
    exit 1
}

echo "PASS: Sparkle pin, live appcast == VERSION, fail-closed release configuration, embedded framework, signature, rpath, and automatic-update plist validated."
