#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

release_contract="docs/NOTCHAGENT_DESK_RELEASE.json"
firmware_package_manifest="firmware/notchagent_desk/release/manifest.json"
jq -e '
  .schemaVersion == 1 and .product == "NotchAgent Desk Beta 1" and
  (keys | sort) == ["appVersion","buildNumber","channel","firmwareVersion","product","protocolVersion","schemaVersion"] and
  .channel == "beta" and .appVersion == "3.1.2" and .buildNumber == "5" and
  .firmwareVersion == "0.6.16" and .protocolVersion == "1.1"
' "$release_contract" >/dev/null || {
    echo "FAIL: invalid NotchAgent Desk Beta 1 release contract." >&2
    exit 1
}

identity="${NOTCHAGENT_SIGN_IDENTITY:-}"
identity_name="$identity"
if [[ "$identity" =~ '^[0-9A-Fa-f]{40}$' ]]; then
    identity_name=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n "/[[:space:]]${identity}[[:space:]]/s/.*\"\([^\"]*\)\".*/\1/p" \
            | head -1
    )
fi
[[ "$identity_name" == "Developer ID Application:"* ]] || {
    echo "NOT READY: set NOTCHAGENT_SIGN_IDENTITY to a Developer ID Application identity." >&2
    exit 2
}

app_version=$(jq -r '.appVersion' "$release_contract")
build_number=$(jq -r '.buildNumber' "$release_contract")
firmware_version=$(jq -r '.firmwareVersion' "$release_contract")

firmware/notchagent_desk/package-release.sh
[[ "$(jq -r '.firmwareVersion' firmware/notchagent_desk/release/manifest.json)" == "$firmware_version" ]] || {
    echo "FAIL: packaged firmware does not match the Beta 1 release contract." >&2
    exit 1
}

NOTCHAGENT_APP_VERSION="$app_version" \
NOTCHAGENT_BUILD_NUMBER="$build_number" \
Scripts/make-app.sh

app="dist/NotchAgent.app"
info="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")" == "$app_version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")" == "$build_number" ]]
codesign --verify --deep --strict --verbose=2 "$app"
signature_details=$(codesign -d --verbose=4 "$app" 2>&1)
print -r -- "$signature_details" | grep -q '^Authority=Developer ID Application:' || {
    echo "FAIL: Beta 1 app is not Developer ID Application signed." >&2
    exit 1
}
print -r -- "$signature_details" | grep -q '^Identifier=br.com.lfrprojects.notchagent$' || {
    echo "FAIL: Beta 1 app bundle identifier is not the release identifier." >&2
    exit 1
}
print -r -- "$signature_details" | grep -q 'flags=.*runtime' || {
    echo "FAIL: Beta 1 app is missing hardened runtime." >&2
    exit 1
}
embedded_manifest="$app/Contents/Resources/DeskFirmware/manifest.json"
jq -e --slurpfile package "$firmware_package_manifest" '
  .schemaVersion == 2 and
  .firmwareVersion == $package[0].firmwareVersion and
  .imageSHA256 == $package[0].imageSHA256 and
  .esptoolSHA256 == $package[0].esptoolSHA256 and
  .sourceSHA256 == $package[0].sourceSHA256
' "$embedded_manifest" >/dev/null || {
    echo "FAIL: embedded Desk firmware differs from the verified release package." >&2
    exit 1
}

echo "PASS: NotchAgent Desk Beta 1 app ${app_version} (${build_number}) is Developer ID signed with firmware ${firmware_version}."
echo "Next: NOTCHAGENT_NOTARY_PROFILE=<profile> Scripts/notarize-app.sh $app"
