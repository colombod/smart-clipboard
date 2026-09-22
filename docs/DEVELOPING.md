# Developing Smart Clipboard

For installation and everyday use, start with the [product guide](../README.md).

## Build and run

Requires Apple Command Line Tools and Swift 6 or later. Open `Package.swift` in Xcode, or run:

```sh
./scripts/build-app.sh
open 'dist/Smart Clipboard.app'
```

SwiftPM fetches pinned Yams and Sparkle dependencies; their licenses are bundled in the app. The default build is ad-hoc signed for local development. Move the app into Applications before enabling launch at login. Opening an already running copy is an explicit reopen and may show its window; cold startup stays in the menu bar.

## Test

```sh
./scripts/test.sh
bash Tests/ReleaseScripts/test-release.sh
python3 Tests/ReleaseScripts/test-release-update.py
python3 Tests/ReleaseScripts/test-compare-bundles.py
```

The ordinary suite uses isolated preferences/history and private pasteboards. Live providers and windowless render snapshots are opt-in; see [oMLX test evidence](testing/OMLX.md) and the [native accessibility harness](../Tests/AccessibilityUITests/README.md). Tests do not replace the real shortcut, selection, focus and paste gates in [UAT.md](UAT.md).

The GitHub `macOS tests` check runs the offline suite and release guards. Durable task tracking uses Beads (`bd`); no keys, real captures, local issue database or build caches belong in source.

## Connections and privacy

[PROVIDERS.md](PROVIDERS.md) records supported request contracts and live verification status. API keys use macOS Keychain. ChatGPT integration uses the official Codex CLI and its own login, not a standalone OAuth client or API-credit substitute. The CLI runs in an isolated temporary directory with image-analysis-only constraints and no user plugins/tools. See the source and provider tests for the enforced boundaries.

Generated HTML/SVG stay inert text. JSON/YAML are validated before acceptance, but syntax validation does not establish extraction accuracy. Keep synthetic evidence separate from private user captures.

## Release

Use the [Developer ID signing, notarization and update guide](SIGNING.md). It covers nested Sparkle signing, Keychain-backed update keys, exact-artifact packaging, resumable notarization, private updater testing and publication checks. Public releases must use a clean reviewed source commit and verified final downloads. The main product README should remain focused on onboarding.
