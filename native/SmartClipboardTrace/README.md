# SmartClipboardTrace

A small native process around **VTracer Rust 0.6.5**, pinned with `Cargo.lock` and Rust 1.94.0. It is bundled at `Smart Clipboard.app/Contents/Helpers/SmartClipboardTrace`. The installed app needs no Rust, Python, Homebrew, model or server.

## Protocol version 1

```sh
SmartClipboardTrace --version
SmartClipboardTrace --input /absolute/capture.png --output /absolute/new-result.svg --preset photo --detail balanced
```

All four conversion flags are required; order is flexible. Unknown, duplicate or missing arguments fail. Presets are `photo`, `logo`, `line-art`; details are `balanced`, `detailed`. Paths must be absolute. Input must be a nonempty regular PNG; an input symlink is rejected. Output must not exist, including a dangling symlink. The helper creates it with mode 0600.

`--version` alone writes one JSON line:

```json
{"name":"SmartClipboardTrace","helperVersion":"1.0.0","engine":"vtracer","version":"0.6.5","protocolVersion":1}
```

A successful conversion writes SVG to the output file and one bounded stdout JSON line containing `engine`, `version`, `paths`, `bytes`, `width`, `height`. Exit code 0 means the output was written successfully. Errors use a nonzero exit and a short controlled stderr message without image data or input paths. The app must not accept an output file from a failed or cancelled process.

Hard limits are 64 MiB compressed input, 8,000 pixels per side, 16,000,000 total decoded pixels, 100,000 output paths and 16 MiB serialized SVG. PNG dimensions are checked before image decoding. The helper applies an 85-second CPU limit and a file-size limit; the app additionally owns its 90-second wall timeout, cancellation/kill, output validation and temporary-directory cleanup. Pixel bounds limit the input workload, but are not a hard process-memory ceiling. A killed process may leave an incomplete output, which the app must discard. The helper does not use a shell, spawn subprocesses or make network requests.

The result contains real vector paths and a viewBox matching source dimensions. It traces the complete supplied image; it does not identify a foreground subject, remove scenery, recover editable text or translate words. Photo inputs can produce large files and many paths. Do not equate a successful trace with a compact semantic reconstruction.

## Presets

- **Photo:** explicit settings matching the evaluated study. Balanced uses speckle 4, colour precision 6 and layer difference 16; detailed uses 2, 8 and 4. Both use corner 60, length 4, iterations 10, splice 45 and path precision 3. These differ deliberately from upstream's built-in Photo preset.
- **Logo:** upstream Poster settings with path precision 3; detailed reduces speckle to 2 and layer difference to 4.
- **Line art:** upstream binary preset with path precision 3, using luminance and white compositing for transparency before its threshold. Detailed reduces speckle to 2. This is monochrome output.

## Build and checks

From the repository root, with the official Rust toolchain and `uv` installed:

```sh
scripts/build-tracer.sh
CARGO_TARGET_DIR="$PWD/.build/tracer" "$HOME/.cargo/bin/cargo" +1.94.0 test --locked --manifest-path native/SmartClipboardTrace/Cargo.toml
uv run --no-project python native/SmartClipboardTrace/test_cli.py --binary .build/tracer/aarch64-apple-darwin/release/SmartClipboardTrace
bash Tests/ReleaseScripts/test-release.sh
```

The build script prints the resulting path and uses macOS 14.0 as the deployment target. On Intel it builds `x86_64-apple-darwin`; the current product release is Apple silicon. It builds only the helper under `.build/`; it neither signs nor installs the app. It preserves caller Rust flags and remaps source and Cargo paths so the release binary does not embed the build machine's home directory. The CLI tests check this privacy property. `build-app.sh` bundles and signs the helper before the app, combines its dependency notices with the app notices, and records helper/lock hashes. Notarization verifies those hashes and the helper's nested signature, hardened runtime and timestamp. These checks do not replace final signed-package and installed-app acceptance.

Dependency licenses are included in `THIRD_PARTY_NOTICES.txt`; `verify-notices.py` checks them against `Cargo.lock`. After an intentional dependency update, produce Cargo metadata and regenerate/review the notices:

```sh
"$HOME/.cargo/bin/cargo" +1.94.0 metadata --locked --format-version 1 --manifest-path native/SmartClipboardTrace/Cargo.toml > .build/tracer-metadata.json
uv run --no-project python native/SmartClipboardTrace/verify-notices.py --generate .build/tracer-metadata.json
```

The `licenses/README.md` explains the few upstream packages that omit their own license files. No binary or Rust cache is checked into the repository.
