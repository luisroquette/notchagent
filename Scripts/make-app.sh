#!/bin/zsh
# Builds NotchAgent.app from the SwiftPM release binary — no Xcode project
# needed. Output: dist/NotchAgent.app. Set NOTCHAGENT_SIGN_IDENTITY to a
# Developer ID or Apple Development identity. Without one, the script uses the
# first local Apple Development identity and falls back to ad-hoc signing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${NOTCHAGENT_APP_VERSION:-$(tr -d '[:space:]' < VERSION)}"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "ERRO: VERSION deve usar SemVer, por exemplo 2.0.0."
    exit 1
fi
BUILD_NUMBER="${NOTCHAGENT_BUILD_NUMBER:-$(tr -d '[:space:]' < BUILD_NUMBER)}"
[[ "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]] || {
    echo "ERRO: NOTCHAGENT_BUILD_NUMBER deve ser um inteiro positivo."
    exit 1
}
CANONICAL_DIST="$PWD/dist"
DIST_INPUT="${NOTCHAGENT_DIST_DIR:-$CANONICAL_DIST}"
mkdir -p "$DIST_INPUT"
DIST=$(cd "$DIST_INPUT" && pwd -P)
[[ "$DIST" == "$PWD"/* && "$DIST" != "$PWD" ]] || {
    echo "ERRO: NOTCHAGENT_DIST_DIR deve permanecer dentro do repositório." >&2
    exit 1
}
FINAL_APP="$DIST/NotchAgent.app"
BUNDLE_IDENTIFIER="${NOTCHAGENT_BUNDLE_IDENTIFIER:-br.com.lfrprojects.notchagent}"
UPDATE_FEED_URL="${NOTCHAGENT_UPDATE_FEED_URL:-}"
UPDATE_PUBLIC_ED_KEY="${NOTCHAGENT_UPDATE_PUBLIC_ED_KEY:-}"
SIGN_IDENTITY="${NOTCHAGENT_SIGN_IDENTITY:-}"
if [[ -n "$UPDATE_FEED_URL" || -n "$UPDATE_PUBLIC_ED_KEY" ]]; then
    [[ "$UPDATE_FEED_URL" =~ '^https://[A-Za-z0-9./_?=&%+~-]+$' &&
       "$UPDATE_PUBLIC_ED_KEY" =~ '^[A-Za-z0-9+/]{43}=$' ]] || {
        echo "NOT READY: configure both a valid HTTPS update feed and Sparkle EdDSA public key." >&2
        exit 1
    }
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk '/"Apple Development:/ { print $2; exit }'
    ) || true
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_CERTIFICATE_NAME="$SIGN_IDENTITY"
if [[ "$SIGN_IDENTITY" =~ '^[0-9A-Fa-f]{40}$' ]]; then
    SIGN_CERTIFICATE_NAME=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n "/[[:space:]]${SIGN_IDENTITY}[[:space:]]/s/.*\"\([^\"]*\)\".*/\1/p" \
            | head -1
    )
    [[ -n "$SIGN_CERTIFICATE_NAME" ]] || {
        echo "NOT READY: NOTCHAGENT_SIGN_IDENTITY fingerprint is not a valid code-signing identity." >&2
        exit 1
    }
fi
SIGN_ARGS=(--force -s "$SIGN_IDENTITY")
if [[ "$SIGN_CERTIFICATE_NAME" == "Developer ID Application:"* ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
    [[ "$UPDATE_FEED_URL" == https://* ]] || {
        echo "NOT READY: Developer ID build requires NOTCHAGENT_UPDATE_FEED_URL with HTTPS." >&2
        exit 1
    }
    [[ "$UPDATE_PUBLIC_ED_KEY" =~ '^[A-Za-z0-9+/]{43}=$' ]] || {
        echo "NOT READY: Developer ID build requires a valid NOTCHAGENT_UPDATE_PUBLIC_ED_KEY." >&2
        exit 1
    }
fi

if [[ "$DIST" == "$CANONICAL_DIST" ]]; then
    running_app=$(pgrep -x NotchAgent 2>/dev/null | head -1 || true)
    [[ -z "$running_app" ]] || {
        echo "FAIL: quit NotchAgent before building; running PID $running_app was left untouched." >&2
        exit 1
    }
fi

build_root=$(mktemp -d "$DIST/.notchagent-build.XXXXXX")
[[ -n "$build_root" && -d "$build_root" && "$build_root" == "$DIST/.notchagent-build."* ]] || exit 1
APP="$build_root/NotchAgent.app"
cleanup() {
    [[ -n "$build_root" && -d "$build_root" && "$build_root" == "$DIST/.notchagent-build."* ]] || return 0
    rm -r -- "$build_root"
}
trap cleanup EXIT

echo "▸ building release binary"
swift build -c release

echo "▸ assembling bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchAgent "$APP/Contents/MacOS/NotchAgent"

SPARKLE_FRAMEWORK=$(find .build/artifacts -path '*/macos-*/Sparkle.framework' -type d -print -quit 2>/dev/null || true)
[[ -n "$SPARKLE_FRAMEWORK" && -d "$SPARKLE_FRAMEWORK" ]] || {
    echo "FAIL: Sparkle.framework was not produced by SwiftPM." >&2
    exit 1
}
echo "▸ embedding Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

DESK_RELEASE="firmware/notchagent_desk/release"
if [[ -f "$DESK_RELEASE/manifest.json" && -x "$DESK_RELEASE/esptool" && -f "$DESK_RELEASE/NotchAgentDesk-factory.bin" ]]; then
    echo "▸ bundling NotchAgent Desk recovery firmware"
    firmware/notchagent_desk/verify-release.sh "$DESK_RELEASE"
    DESK_RESOURCES="$APP/Contents/Resources/DeskFirmware"
    mkdir -p "$DESK_RESOURCES"
    cp "$DESK_RELEASE/NotchAgentDesk-factory.bin" "$DESK_RESOURCES/"
    cp "$DESK_RELEASE/esptool" "$DESK_RESOURCES/"
    cp "$DESK_RELEASE/esptool-LICENSE.txt" "$DESK_RESOURCES/"
    ESPTOOL_SIGN_ARGS=("${SIGN_ARGS[@]}")
    if [[ "$SIGN_CERTIFICATE_NAME" == "Developer ID Application:"* ]]; then
        ESPTOOL_ENTITLEMENTS="Resources/DeskFirmwareEsptool.entitlements.plist"
        plutil -lint "$ESPTOOL_ENTITLEMENTS" >/dev/null
        ESPTOOL_SIGN_ARGS+=(--entitlements "$ESPTOOL_ENTITLEMENTS")
    fi
    codesign "${ESPTOOL_SIGN_ARGS[@]}" "$DESK_RESOURCES/esptool"
    if [[ "$SIGN_CERTIFICATE_NAME" == "Developer ID Application:"* ]]; then
        helper_entitlements=$(codesign -d --entitlements :- "$DESK_RESOURCES/esptool" 2>/dev/null)
        [[ "$helper_entitlements" == *"com.apple.security.cs.disable-library-validation"* ]] || {
            echo "FAIL: signed Desk flasher is missing its isolated library-validation entitlement." >&2
            exit 1
        }
    fi
    DESK_FW_VERSION=$(sed -n 's/^#define DESK_FW_VERSION "\([0-9][0-9.]*\)"$/\1/p' firmware/notchagent_desk/config.h)
    DESK_SOURCE_SHA=$(jq -er '.sourceSHA256 | select(test("^[0-9a-f]{64}$"))' "$DESK_RELEASE/manifest.json")
    swift firmware/notchagent_desk/package_manifest.swift "$DESK_FW_VERSION" \
        "$DESK_RESOURCES/NotchAgentDesk-factory.bin" "$DESK_RESOURCES/esptool" \
        "$DESK_SOURCE_SHA" "$DESK_RESOURCES/manifest.json"
    firmware/notchagent_desk/verify-release.sh "$DESK_RESOURCES"
else
    echo "▸ Desk recovery firmware not packaged; run firmware/notchagent_desk/package-release.sh"
fi

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleName</key><string>NotchAgent</string>
    <key>CFBundleDisplayName</key><string>NotchAgent</string>
    <key>CFBundleExecutable</key><string>NotchAgent</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [[ -n "$UPDATE_FEED_URL" ]]; then
    plutil -insert SUFeedURL -string "$UPDATE_FEED_URL" "$APP/Contents/Info.plist"
    plutil -insert SUPublicEDKey -string "$UPDATE_PUBLIC_ED_KEY" "$APP/Contents/Info.plist"
    plutil -insert SUEnableAutomaticChecks -bool true "$APP/Contents/Info.plist"
    plutil -insert SUAutomaticallyUpdate -bool true "$APP/Contents/Info.plist"
fi

echo "▸ generating icon"
ICONDIR="$build_root/AppIcon.iconset"
mkdir -p "$ICONDIR"
swift Scripts/gen-icon.swift "$ICONDIR/icon_512x512@2x.png"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512"; do
    px=${spec%% *}
    name=${spec##* }
    sips -z "$px" "$px" "$ICONDIR/icon_512x512@2x.png" --out "$ICONDIR/$name.png" > /dev/null
done
iconutil -c icns "$ICONDIR" -o "$APP/Contents/Resources/AppIcon.icns"

if [[ "$SIGN_CERTIFICATE_NAME" == "Developer ID Application:"* ]]; then
    echo "▸ signing (Developer ID Application)"
else
    echo "▸ signing (development)"
fi
codesign --deep "${SIGN_ARGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_ARGS[@]}" "$APP"

backup=""
if [[ -e "$FINAL_APP" ]]; then
    backup_root=$(mktemp -d "$DIST/.notchagent-previous.XXXXXX")
    [[ -n "$backup_root" && -d "$backup_root" && "$backup_root" == "$DIST/.notchagent-previous."* ]] || exit 1
    backup="$backup_root/NotchAgent.app"
    mv -- "$FINAL_APP" "$backup"
fi
if ! mv -- "$APP" "$FINAL_APP"; then
    echo "FAIL: new app could not be installed; previous app remains at ${backup:-none}." >&2
    exit 1
fi

echo "✓ $FINAL_APP pronto ($(du -sh "$FINAL_APP" | cut -f1))"
[[ -z "$backup" ]] || echo "  versão anterior preservada: $backup"
echo "  instalar: cp -R $FINAL_APP /Applications/"
