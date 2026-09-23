#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# This app uses the production views with compile-time isolated dependencies.
# It never replaces the installed app and is not a distributable release.
AUDIT_BUILD="$PWD/.build/accessibility-audit"
swift build -c debug --scratch-path "$AUDIT_BUILD" --disable-sandbox -Xswiftc -DACCESSIBILITY_AUDIT
BIN_DIR="$(swift build -c debug --scratch-path "$AUDIT_BUILD" --show-bin-path --disable-sandbox -Xswiftc -DACCESSIBILITY_AUDIT)"
mkdir -p "$PWD/dist"
STAGING="$(mktemp -d "$PWD/dist/accessibility-audit.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Smart Clipboard Audit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SmartClipboard" "$APP/Contents/MacOS/SmartClipboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt"
cp -R "$BIN_DIR/SmartClipboard_ClipboardCore.bundle" "$APP/Contents/Resources/"
for LOCALIZATION in Resources/*.lproj; do
    cp -R "$LOCALIZATION" "$APP/Contents/Resources/"
done
./scripts/embed-sparkle.sh "$APP" "$BIN_DIR"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.smartclipboard.accessibility-audit' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Smart Clipboard Audit' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Smart Clipboard Audit' "$APP/Contents/Info.plist"
swift scripts/generate-icon.swift "$AUDIT_BUILD/AppIcon.iconset"
iconutil -c icns "$AUDIT_BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
rm -rf "$PWD/dist/Smart Clipboard Audit.app"
mv "$APP" "$PWD/dist/Smart Clipboard Audit.app"
echo "Built isolated audit app: $PWD/dist/Smart Clipboard Audit.app"
