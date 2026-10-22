#!/usr/bin/env bash
# Builds a release Sysbar.app (ad-hoc signed) into ./build.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/strings.py check

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Sysbar"
APP="build/Sysbar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sysbar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "$APP"
