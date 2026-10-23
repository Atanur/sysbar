#!/usr/bin/env bash
# Builds a release Sysbar.app (ad-hoc signed) into ./build.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/strings.py check

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
APP="build/Sysbar.app"
HELPER_ID="com.atanur.sysbar.fanhelper"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN_DIR/Sysbar" "$APP/Contents/MacOS/Sysbar"
# The fan helper and the launchd job that SMAppService registers for it.
cp "$BIN_DIR/SysbarFanHelper" "$APP/Contents/MacOS/SysbarFanHelper"
cp "Resources/LaunchDaemons/$HELPER_ID.plist" "$APP/Contents/Library/LaunchDaemons/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
# Inner code first, under the identifier the app requires of the helper.
codesign --force --sign - --identifier "$HELPER_ID" "$APP/Contents/MacOS/SysbarFanHelper"
codesign --force --sign - "$APP"

echo "$APP"
