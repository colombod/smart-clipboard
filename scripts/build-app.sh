#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
SOURCE_COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
SOURCE_DIRTY="$(git status --porcelain --untracked-files=normal 2>/dev/null || true)"
# Remap both source literals and debug information, including C dependencies.
# Bash arrays keep build paths containing spaces as one compiler argument.
PRIVACY_BUILD_FLAGS=()
for SOURCE_PREFIX in "$HOME" "$PWD"; do
    PRIVACY_BUILD_FLAGS+=(
        -Xswiftc -file-prefix-map -Xswiftc "$SOURCE_PREFIX=/smart-clipboard-build"
        -Xswiftc -debug-prefix-map -Xswiftc "$SOURCE_PREFIX=/smart-clipboard-build"
        -Xcc "-ffile-prefix-map=$SOURCE_PREFIX=/smart-clipboard-build"
        -Xcc "-fdebug-prefix-map=$SOURCE_PREFIX=/smart-clipboard-build"
    )
done
swift build -c release --disable-sandbox "${PRIVACY_BUILD_FLAGS[@]}"
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
BUILD_OUTPUT_DIR="${BUILD_OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$BUILD_OUTPUT_DIR"
STAGING="$(mktemp -d "$BUILD_OUTPUT_DIR/build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Smart Clipboard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
TRACER="$(./scripts/build-tracer.sh)"
mkdir -p "$APP/Contents/Helpers"
cp "$TRACER" "$APP/Contents/Helpers/SmartClipboardTrace"
chmod 755 "$APP/Contents/Helpers/SmartClipboardTrace"
cp "$BIN_DIR/SmartClipboard" "$APP/Contents/MacOS/SmartClipboard"
# Mach-O linker debug records also contain absolute object/module filenames.
# Remove debug symbols from the shipping copy before signing; keep build outputs.
strip -S "$APP/Contents/MacOS/SmartClipboard"
uv run --no-project python - "$APP" <<'PY'
import os, pathlib, sys
app = pathlib.Path(sys.argv[1])
prefixes = {b'/Users/', b'/home/', os.fsencode(pathlib.Path.home()) + b'/'}
for relative in ['Contents/MacOS/SmartClipboard', 'Contents/Helpers/SmartClipboardTrace']:
    binary = (app / relative).read_bytes()
    if any(prefix in binary for prefix in prefixes):
        raise SystemExit(f'Build privacy check failed for {pathlib.Path(relative).name}: build-machine home paths remain.')
PY
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt"
cat native/SmartClipboardTrace/THIRD_PARTY_NOTICES.txt >> "$APP/Contents/Resources/ThirdPartyNotices.txt"
cp native/SmartClipboardTrace/Cargo.lock "$APP/Contents/Resources/TraceCargo.lock"
cp -R "$BIN_DIR/SmartClipboard_ClipboardCore.bundle" "$APP/Contents/Resources/"
for LOCALIZATION in Resources/*.lproj; do
    cp -R "$LOCALIZATION" "$APP/Contents/Resources/"
done
./scripts/embed-sparkle.sh "$APP" "$BIN_DIR"
swift scripts/generate-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns "$PWD/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/SmartClipboardTrace"
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP/Contents/Helpers/SmartClipboardTrace"
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
rm -rf "$BUILD_OUTPUT_DIR/Smart Clipboard.app"
mv "$APP" "$BUILD_OUTPUT_DIR/Smart Clipboard.app"
APP="$BUILD_OUTPUT_DIR/Smart Clipboard.app"
SOURCE_COMMIT="$SOURCE_COMMIT" SOURCE_DIRTY="$SOURCE_DIRTY" uv run --no-project python - "$APP" <<'PY'
import hashlib, json, os, pathlib, sys
app = pathlib.Path(sys.argv[1])
(app.parent / 'build-source.json').write_text(json.dumps({
    'commit': os.environ['SOURCE_COMMIT'], 'dirty': bool(os.environ['SOURCE_DIRTY']),
    'executableSHA256': hashlib.sha256((app / 'Contents/MacOS/SmartClipboard').read_bytes()).hexdigest(),
    'tracerSHA256': hashlib.sha256((app / 'Contents/Helpers/SmartClipboardTrace').read_bytes()).hexdigest(),
    'tracerLockSHA256': hashlib.sha256((app / 'Contents/Resources/TraceCargo.lock').read_bytes()).hexdigest()
}, indent=2) + '\n')
PY
echo "Built $APP"
