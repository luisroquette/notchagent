#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

release_contract="docs/NOTCHAGENT_DESK_RELEASE.json"
app_version=$(jq -er '.appVersion | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$release_contract")
build_number=$(jq -er '.buildNumber | select(test("^[1-9][0-9]*$"))' "$release_contract")
firmware_version=$(jq -er '.firmwareVersion | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$release_contract")

NOTCHAGENT_APP_VERSION="$app_version" \
NOTCHAGENT_BUILD_NUMBER="$build_number" \
Scripts/make-app.sh

app="dist/NotchAgent.app"
info="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")" == "$app_version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")" == "$build_number" ]]
[[ "$(jq -r '.firmwareVersion' "$app/Contents/Resources/DeskFirmware/manifest.json")" == "$firmware_version" ]]
codesign --verify --deep --strict "$app"

echo "PASS: local Beta 1 app ${app_version} (${build_number}) includes firmware ${firmware_version}."
