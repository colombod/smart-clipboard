#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# Some Command Line Tools releases don't discover Swift Testing macros automatically.
TOOLCHAIN_BIN="$(dirname "$(xcrun --find swiftc)")"
TEST_PLUGINS="$TOOLCHAIN_BIN/../lib/swift/host/plugins/testing"
if [[ -d "$TEST_PLUGINS" ]]; then
    swift test --disable-sandbox -Xswiftc -plugin-path -Xswiftc "$TEST_PLUGINS"
else
    swift test --disable-sandbox
fi
