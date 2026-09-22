#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
SOURCE_COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
SOURCE_DIRTY="$(git status --porcelain --untracked-files=normal 2>/dev/null || true)"
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
mkdir -p "$PWD/dist"
STAGING="$(mktemp -d "$PWD/dist/build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Smart Clipboard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SmartClipboard" "$APP/Contents/MacOS/SmartClipboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt"
./scripts/embed-sparkle.sh "$APP" "$BIN_DIR"
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
SOURCE_COMMIT="$SOURCE_COMMIT" SOURCE_DIRTY="$SOURCE_DIRTY" python3 - "$APP" <<'PY'
import hashlib, json, os, pathlib, sys
app = pathlib.Path(sys.argv[1])
(app.parent / 'build-source.json').write_text(json.dumps({
    'commit': os.environ['SOURCE_COMMIT'], 'dirty': bool(os.environ['SOURCE_DIRTY']),
    'executableSHA256': hashlib.sha256((app / 'Contents/MacOS/SmartClipboard').read_bytes()).hexdigest()
}, indent=2) + '\n')
PY
echo "Built $APP"
