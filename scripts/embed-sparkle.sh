#!/bin/bash
# Sparkle's manual distribution signing order; never sign with --deep.
set -euo pipefail
APP="${1:?App bundle required}"
BIN_DIR="${2:?SwiftPM binary directory required}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORK="${SPARKLE_FRAMEWORK:-$BIN_DIR/Sparkle.framework}"
if [[ ! -d "$FRAMEWORK" && -z "${SPARKLE_FRAMEWORK:-}" ]]; then
    FRAMEWORK="$REPO/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
[[ -d "$FRAMEWORK" ]] || { echo "Sparkle.framework is missing; resolve the pinned package before packaging." >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$FRAMEWORK/Resources/Info.plist")"
[[ "$VERSION" == 2.10.0 ]] || { echo "Expected pinned Sparkle 2.10.0, found $VERSION." >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SIGN=(--force --options runtime --sign "${SIGNING_IDENTITY:--}")
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then SIGN+=(--timestamp); fi
for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    target="$FRAMEWORK/Versions/B/$helper"
    [[ -e "$target" ]] || { echo "Missing Sparkle helper: $helper" >&2; exit 1; }
    if [[ "$helper" == XPCServices/Downloader.xpc ]]; then
        codesign "${SIGN[@]}" --preserve-metadata=entitlements "$target"
    else
        codesign "${SIGN[@]}" "$target"
    fi
done
codesign "${SIGN[@]}" "$FRAMEWORK"
codesign --verify --deep --strict "$FRAMEWORK"
# SwiftPM's executable is moved into an app; provide the bundle's runtime path.
if ! otool -l "$APP/Contents/MacOS/SmartClipboard" | awk '/cmd LC_RPATH/{getline; getline; print $2}' | /usr/bin/grep -Fxq '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/SmartClipboard"
fi
