#!/bin/bash
# Builds build/Macndroid.app. Set BUNDLE_ADB=1 to copy adb into the app so it works without the Android SDK.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Macndroid.app"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

if [ ! -f Resources/AppIcon.icns ]; then
    echo "▸ Generating icon…"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    swift scripts/make-icon.swift "$ICONSET"
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

echo "▸ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Macndroid" "$APP/Contents/MacOS/Macndroid"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ "${BUNDLE_ADB:-0}" = "1" ]; then
    ADB="$(command -v adb || true)"
    [ -z "$ADB" ] && ADB="$HOME/Library/Android/sdk/platform-tools/adb"
    [ -x "$ADB" ] || { echo "adb not found; install android-platform-tools"; exit 1; }
    mkdir -p "$APP/Contents/Resources/platform-tools"
    cp "$ADB" "$APP/Contents/Resources/platform-tools/adb"
    echo "  bundled adb from $ADB"
fi

codesign --force --deep --sign - "$APP" >/dev/null
echo "✓ Built $APP"
