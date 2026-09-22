#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
EXISTING_BUILD=false
DEFER_CHECKSUMS=false
for argument in "$@"; do
    case "$argument" in
        --existing-build) EXISTING_BUILD=true ;;
        --defer-checksums) DEFER_CHECKSUMS=true ;;
        *) echo "Usage: $0 [--existing-build] [--defer-checksums]" >&2; exit 2 ;;
    esac
done
if [[ "$EXISTING_BUILD" == false ]]; then ./scripts/build-app.sh; fi
APP="$PWD/dist/Smart Clipboard.app"
[[ -f "$APP/Contents/Info.plist" && -x "$APP/Contents/MacOS/SmartClipboard" ]] || { echo "No complete existing app build at $APP" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
[[ "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid app version for release filename." >&2; exit 1; }
BASE="Smart-Clipboard-${VERSION}-macOS-${ARCH}"
STAGING="$(mktemp -d "$PWD/dist/package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Smart Clipboard.app"
codesign --verify --deep --strict "$STAGING/Smart Clipboard.app"
diff -qr "$APP" "$STAGING/Smart Clipboard.app"
ln -s /Applications "$STAGING/Applications"
cp docs/INSTALL.txt "$STAGING/INSTALL.txt"
rm -f "$PWD/dist/SHA256SUMS.txt"
hdiutil create -volname 'Smart Clipboard' -srcfolder "$STAGING" -format UDZO -ov "$PWD/dist/$BASE.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/$BASE.zip"
if [[ "$DEFER_CHECKSUMS" == false ]]; then
    (cd dist && shasum -a 256 "$BASE.dmg" "$BASE.zip" > SHA256SUMS.txt)
fi
echo "Release assets are in $PWD/dist"
