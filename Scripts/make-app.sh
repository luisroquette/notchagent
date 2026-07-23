#!/bin/zsh
# Builds NotchAgent.app from the SwiftPM release binary — no Xcode project
# needed. Output: dist/NotchAgent.app (signed with local Apple Development
# identity so Keychain ACL grants persist across rebuilds; use Developer ID
# + notarization for public distribution).
SIGN_IDENTITY="Apple Development: luis roquette (K74FG72F9W)"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0.0"
APP="dist/NotchAgent.app"

echo "▸ stopping running instances"
pkill -9 -f "NotchAgent.app/Contents/MacOS/NotchAgent" 2>/dev/null || true
pkill -9 -f ".build/debug/NotchAgent" 2>/dev/null || true

echo "▸ building release binary"
swift build -c release

echo "▸ assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchAgent "$APP/Contents/MacOS/NotchAgent"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>br.com.lfrprojects.notchagent</string>
    <key>CFBundleName</key><string>NotchAgent</string>
    <key>CFBundleDisplayName</key><string>NotchAgent</string>
    <key>CFBundleExecutable</key><string>NotchAgent</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "▸ generating icon"
ICONDIR=$(mktemp -d)/AppIcon.iconset
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

echo "▸ signing ($SIGN_IDENTITY)"
codesign --force --deep -s "$SIGN_IDENTITY" "$APP"

echo "✓ $APP pronto ($(du -sh "$APP" | cut -f1))"
echo "  instalar: cp -R $APP /Applications/"
