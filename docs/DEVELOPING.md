# Developing Smart Clipboard

For installation and everyday use, start with the [product guide](../README.md).

## Build and run

Requires Apple Command Line Tools, Swift 6 or later, `uv`, and the official Rust toolchain (pinned to 1.94.0 for the tracing helper). These are development dependencies; the installed app needs none of them. Open `Package.swift` in Xcode for Swift work, or build the complete app with:

```sh
./scripts/build-app.sh
open 'dist/Smart Clipboard.app'
```

SwiftPM fetches pinned Yams and Sparkle dependencies. The build also compiles the pinned [native VTracer helper](../native/SmartClipboardTrace/README.md), bundles its dependency notices and signs it before the outer app. The default build is ad-hoc signed for local development. Do not replace a working Developer ID installation with an ad-hoc copy: use `BUILD_OUTPUT_DIR` for separate candidate artifacts. Opening an already running copy is an explicit reopen and may show its window; cold startup stays in the menu bar.

Release builds remap Swift, C and Rust source paths and remove linker debug records from the shipping executable. A pre-signing check rejects either app-owned executable if it still contains a build-machine home path. The original build outputs remain available for local debugging; they are not release assets.

## Test

```sh
TRACE_HELPER="$(./scripts/build-tracer.sh)"
SMART_CLIPBOARD_TRACE_HELPER="$TRACE_HELPER" ./scripts/test.sh
uv run --no-project python native/SmartClipboardTrace/test_cli.py --binary "$TRACE_HELPER"
bash Tests/ReleaseScripts/test-release.sh
uv run --no-project python Tests/ReleaseScripts/test-release-update.py
uv run --no-project python Tests/ReleaseScripts/test-compare-bundles.py
uv run --no-project python Tests/ReleaseScripts/test-localizations.py
uv run --no-project python scripts/check-localizations.py
```

The ordinary suite uses isolated preferences/history and private pasteboards. Live providers and windowless render snapshots are opt-in; see [oMLX test evidence](testing/OMLX.md) and the [native accessibility harness](../Tests/AccessibilityUITests/README.md). Tests do not replace the real shortcut, selection, focus and paste gates in [UAT.md](UAT.md).

The GitHub `macOS tests` check runs the offline suite and release guards. Durable task tracking uses Beads (`bd`); no keys, real captures, local issue database or build caches belong in source.

## Interface and output languages

Wrap interface literals in `L10n.text("…")`; interpolated values become positional catalog arguments and remain literal user content. Do not localize stored IDs, provider wire keys, model names or AI prompts. After adding UI text, run `uv run --no-project python scripts/check-localizations.py --write-english`, translate all added keys in the four other catalogs, then run the checker. Main-bundle permission text lives in `Resources/<language>.lproj/InfoPlist.strings`.

The build scripts embed the shared translation bundle and permission resources. Verify a development package with `uv run --no-project python scripts/check-localizations.py --app '/path/Smart Clipboard.app'`; `BUILD_OUTPUT_DIR` lets the build script use a temporary folder without replacing existing release artifacts. [Language testing](testing/LANGUAGES.md) explains isolated rendering and local-model checks.

`OutputLanguage` controls capture content independently of UI language. Targets are resolved when an operation starts. History stores a resolved language per result, with explicit null for source and `und` for pre-picker directions whose output language is unknown. The explicit null distinguishes new source-language choices from legacy history that lacks the field.

## Connections and privacy

[PROVIDERS.md](PROVIDERS.md) records supported request contracts and live verification status. API keys use macOS Keychain. ChatGPT integration uses the official Codex CLI and its own login, not a standalone OAuth client or API-credit substitute. The CLI runs in an isolated temporary directory with image-analysis-only constraints and no user plugins/tools. See the source and provider tests for the enforced boundaries.

Generated HTML/SVG stay inert text. JSON/YAML and a bounded static subset of SVG are validated before acceptance, but syntax validation does not establish extraction accuracy. SVG supports inline local resource references; resource references inside stylesheets are intentionally unsupported. Keep synthetic evidence separate from private user captures.

Local tracing is an execution route separate from AI providers and Apple Vision OCR. Snapshot the method and settings before selection, bypass AI readiness and credentials for trace/image routes, and check cancellation before saving or copying. History keys results by method as well as format/language and trace settings. Results above 64 KiB use private immutable artifact files with integrity checks; the JSON index contains metadata. The original PNG remains available if a result artifact is damaged. Test upgrades on an isolated history copy, and retain a backup before testing a downgrade to a version that predates artifact storage.

[Tracing verification](testing/TRACING.md) records measured fixture results, automated coverage and the remaining native release gates.

## Release

Use the [Developer ID signing, notarization and update guide](SIGNING.md). It covers nested Sparkle signing, Keychain-backed update keys, exact-artifact packaging, resumable notarization, private updater testing and publication checks. Public releases must use a clean reviewed source commit and verified final downloads. The main product README should remain focused on onboarding.
