#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
mkdir -p "$PWD/dist"
STAGING="$(mktemp -d "$PWD/dist/build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Smart Clipboard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SmartClipboard" "$APP/Contents/MacOS/SmartClipboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/generate-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns "$PWD/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
rm -rf "$PWD/dist/Smart Clipboard.app"
mv "$APP" "$PWD/dist/Smart Clipboard.app"
APP="$PWD/dist/Smart Clipboard.app"
echo "Built $APP"
