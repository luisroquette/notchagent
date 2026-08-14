#!/bin/zsh
# Generates a signed Sparkle appcast locally. It never uploads or publishes.
set -euo pipefail
cd "$(dirname "$0")/.."

release_contract="docs/NOTCHAGENT_DESK_RELEASE.json"
version=$(jq -er '.appVersion' "$release_contract")
asset="${1:-dist/NotchAgent-Desk-Beta1-${version}.zip}"
output_dir="${2:-dist/updates}"
feed_url="${NOTCHAGENT_UPDATE_FEED_URL:-}"
download_prefix="${NOTCHAGENT_UPDATE_DOWNLOAD_URL_PREFIX:-}"
public_key="${NOTCHAGENT_UPDATE_PUBLIC_ED_KEY:-}"
key_account="${NOTCHAGENT_SPARKLE_KEY_ACCOUNT:-br.com.lfrprojects.notchagent}"
tool=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
key_tool=".build/artifacts/sparkle/Sparkle/bin/generate_keys"

[[ -f "$asset" && "$asset" == *.zip ]] || {
    echo "NOT READY: notarized release ZIP not found: $asset" >&2
    exit 2
}
[[ "$feed_url" =~ '^https://[A-Za-z0-9./_?=&%+~-]+$' ]] || {
    echo "NOT READY: set NOTCHAGENT_UPDATE_FEED_URL to the final HTTPS appcast URL." >&2
    exit 2
}
[[ "$download_prefix" =~ '^https://[A-Za-z0-9./_?=&%+~-]+/$' ]] || {
    echo "NOT READY: set NOTCHAGENT_UPDATE_DOWNLOAD_URL_PREFIX to an HTTPS URL ending in /." >&2
    exit 2
}
[[ "$public_key" =~ '^[A-Za-z0-9+/]{43}=$' ]] || {
    echo "NOT READY: set NOTCHAGENT_UPDATE_PUBLIC_ED_KEY to the Sparkle public key." >&2
    exit 2
}
[[ -x "$tool" && -x "$key_tool" ]] || {
    echo "NOT READY: run swift package resolve to install Sparkle tools." >&2
    exit 2
}

installed_public_key=$("$key_tool" --account "$key_account" -p 2>/dev/null || true)
[[ "$installed_public_key" == "$public_key" ]] || {
    echo "NOT READY: the configured public key does not match the Keychain account $key_account." >&2
    exit 2
}

mkdir -p "$output_dir"
target_asset="$output_dir/${asset:t}"
[[ ! -e "$target_asset" ]] || {
    echo "NOT READY: preserve the existing update asset and choose a new output directory." >&2
    exit 2
}
ditto "$asset" "$target_asset"
feed_filename="${feed_url##*/}"
[[ "$feed_filename" =~ '^[A-Za-z0-9._-]+\.xml$' ]] || {
    echo "NOT READY: update feed URL must end in a safe XML filename." >&2
    exit 2
}
"$tool" --account "$key_account" --download-url-prefix "$download_prefix" \
    -o "$output_dir/$feed_filename" "$output_dir"

appcast="$output_dir/$feed_filename"
[[ -s "$appcast" ]] || {
    echo "FAIL: Sparkle did not generate the expected appcast." >&2
    exit 1
}
echo "PASS: signed appcast generated locally at $appcast. Nothing was uploaded."
