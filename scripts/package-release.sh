#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
APP="$PWD/dist/Smart Clipboard.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
BASE="Smart-Clipboard-${VERSION}-macOS-${ARCH}"
STAGING="$(mktemp -d "$PWD/dist/package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Smart Clipboard.app"
ln -s /Applications "$STAGING/Applications"
cp docs/INSTALL.txt "$STAGING/INSTALL.txt"
hdiutil create -volname 'Smart Clipboard' -srcfolder "$STAGING" -format UDZO -ov "$PWD/dist/$BASE.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/$BASE.zip"
(cd dist && shasum -a 256 "$BASE.dmg" "$BASE.zip" > SHA256SUMS.txt)
echo "Release assets are in $PWD/dist"
