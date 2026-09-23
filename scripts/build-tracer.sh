#!/bin/bash
# Build the pinned native helper only. Does not sign, install, or modify dist.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# == 0 ]] || { echo 'Usage: scripts/build-tracer.sh' >&2; exit 1; }
CARGO="$(command -v cargo || true)"
[[ -n "$CARGO" ]] || CARGO="$HOME/.cargo/bin/cargo"
[[ -x "$CARGO" ]] || { echo 'Install Rust with rustup from https://rustup.rs, then retry.' >&2; exit 1; }
case "$(uname -sm)" in
    'Darwin arm64') TARGET=aarch64-apple-darwin ;;
    'Darwin x86_64') TARGET=x86_64-apple-darwin ;;
    *) echo 'The bundled tracing helper must be built on macOS.' >&2; exit 1 ;;
esac
cd "$ROOT/native/SmartClipboardTrace"
export MACOSX_DEPLOYMENT_TARGET=14.0
# Cargo's encoded form preserves each existing flag without shell evaluation,
# including paths with spaces. Keep build-machine paths out of panic strings.
uv run --no-project python - "$CARGO" "$TARGET" "$ROOT" <<'PY' >&2
import os
from pathlib import Path
import subprocess
import sys

cargo, target, root = sys.argv[1:]
environment = os.environ.copy()
if 'CARGO_ENCODED_RUSTFLAGS' in environment:
    flags = environment['CARGO_ENCODED_RUSTFLAGS'].split('\x1f') if environment['CARGO_ENCODED_RUSTFLAGS'] else []
else:
    # This is Cargo's whitespace-separated RUSTFLAGS format, not shell syntax.
    flags = environment.get('RUSTFLAGS', '').split()
for path, replacement in [
    (Path.home(), '/build-home'),
    (Path(environment.get('CARGO_HOME', Path.home() / '.cargo')), '/cargo'),
    (Path(root), '/smart-clipboard'),
]:
    for source in dict.fromkeys([str(path), str(path.resolve())]):
        flags.append(f'--remap-path-prefix={source}={replacement}')
environment['CARGO_ENCODED_RUSTFLAGS'] = '\x1f'.join(flags)
subprocess.run([cargo, '+1.94.0', 'build', '--locked', '--release', '--target', target,
                '--target-dir', str(Path(root) / '.build/tracer')], env=environment, check=True)
PY
uv run --no-project python verify-notices.py >&2
printf '%s\n' "$ROOT/.build/tracer/$TARGET/release/SmartClipboardTrace"
