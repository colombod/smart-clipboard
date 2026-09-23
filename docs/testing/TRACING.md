# Local SVG tracing verification

Development build 13 adds the bundled native VTracer 0.6.5 helper. The results below were measured on 23 September 2026 on an Apple Silicon development Mac. They establish implementation and fixture behavior, not completion of the native capture or public-release gates in [UAT](../UAT.md#local-svg-tracing-candidate).

## Fixture comparison

The native helper reproduced every path's geometry from the earlier VTracer feasibility study for three photo fixtures at both detail settings. The helper adds an SVG `viewBox`; the file bytes therefore differ from the study output. All six outputs passed the app's static SVG validator and contained vector paths without embedded raster images.

| Photo fixture | Detail | Paths | SVG bytes | Helper time |
| --- | --- | ---: | ---: | ---: |
| Mug, 1254 × 1254 | Balanced | 602 | 341,579 | 0.15 s |
| Mug, 1254 × 1254 | Detailed | 10,746 | 5,532,487 | 1.29 s |
| Cat, 1254 × 1254 | Balanced | 4,867 | 2,736,098 | 0.47 s |
| Cat, 1254 × 1254 | Detailed | 20,150 | 7,801,229 | 1.38 s |
| Kitten from [issue #3](https://github.com/colombod/smart-clipboard/issues/3), 952 × 1024 | Balanced | 1,928 | 1,051,330 | 0.18 s |
| Same kitten | Detailed | 12,192 | 4,913,511 | 0.67 s |

These are single local measurements, not performance guarantees. App validation, storage and copying add time. The detailed kitten app integration test, including a fresh history reopen, completed in approximately 4.5 seconds. The trace follows visible silhouettes, markings and colours, but colour banding and small artifacts remain. Text becomes outlines, backgrounds remain, and tracing does not recover chart data or translate words.

## Automated checks

The app and core run contained 247 tests: 242 passed and five opt-in tests were skipped. The run enabled the actual native helper and detailed kitten fixture. It covered provider-independent dispatch, settings snapshots, cancellation and failure preserving the clipboard, distinct AI/OCR/trace variants, large result storage, integrity checks, and reopening the exact SVG after creating a fresh app model. Its pasteboard and preferences were isolated from the installed app.

Rust unit tests, native CLI tests, release orchestration and publication guards also passed. CLI tests cover all presets and detail levels, malformed arguments, unsafe file paths, image limits and output protection. Release checks verify the nested helper signature and its recorded hash alongside the dependency lockfile.

Separate offscreen render checks passed for English, Italian, Spanish, French and German in light and dark appearances at the minimum editor size. Large SVGs use a compact result summary with complete Copy and Save actions. These checks do not establish native VoiceOver, keyboard navigation or system high-contrast support.

To repeat the native app integration with a locally available photo:

```sh
TRACE_HELPER="$(./scripts/build-tracer.sh)"
SMART_CLIPBOARD_TRACE_HELPER="$TRACE_HELPER" \
SMART_CLIPBOARD_TRACE_FIXTURE="/absolute/path/to/photo.png" \
./scripts/test.sh
```

Use a detailed photo whose SVG exceeds 128 KiB for the large-artifact regression. The default offline suite does not download the study fixtures.

## Remaining release gates

Signed installation, global-shortcut region/window selection, focus restoration, real paste, and notification observations still require the exact release candidate. Their status stays **NOT RUN** until recorded as native evidence. Development builds and imported-image tests must not be substituted for those observations. The existing installed version and public update feed remain unchanged until the candidate passes the required gates.
