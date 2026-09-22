# Local vision test evidence — 22 September 2026

The downloaded `mlx-community/Qwen3-VL-8B-Instruct-4bit` and `mlx-community/Qwen3-VL-32B-Instruct-4bit` can read images and produce structured results. **Description and SVG quality remain public-release blockers with the current app prompt.** The official packaged oMLX 0.7.0.dev2 fixes the structured-output failure, but both models still produced invented observations or inaccurate vector geometry. Structural checks do not establish all-format quality or the native capture workflow.

## Environment and server compatibility

Tests used an M5 Max Mac with 128 GiB memory, macOS 26.7 (25G229), the multiple-provider development candidate, and the complete Qwen3-VL-8B-Instruct-4bit checkpoint. The initial compatibility diagnostic used oMLX 0.6.4, with mlx-vlm 0.6.3 and MLX 0.32.0.

The user's running server on port 8999 extracted a generated screenshot exactly in 3.74 seconds, including a random reference visible only in the image. The same image with a required JSON envelope failed: repeated/corrupted text, an unfinished response, and `finish_reason: length`. Smart Clipboard rejects this incomplete result.

This reproduced the upstream VLM grammar bug in [issue #3550](https://github.com/jundot/omlx/issues/3550). A separate loopback process on port 9000 applied the tokenizer resolver from [PR #3551](https://github.com/jundot/omlx/pull/3551), commit `ae04a79233dedccd32c0781aa172d1faf8d2b438`, **in memory**. The process used isolated settings/cache directories and was stopped after testing. No installed oMLX files or user settings were patched. The same structured probe then completed with exact extracted text in 5.67 seconds, including cold model loading.

[oMLX 0.7.0.dev2](https://github.com/jundot/omlx/releases/tag/v0.7.0.dev2) includes this fix and remains a prerelease. Later testing used the **unmodified official macOS 26/27 DMG**, extracted separately and served on loopback port 9000 with isolated state and Hugging Face offline mode. Its [published SHA-256](https://github.com/jundot/omlx/releases/expanded_assets/v0.7.0.dev2) is `5741d9db598a3c00de0564fb8c65349df7cf51913787999adf65d380b3942137`. The packaged-server results below supersede the earlier limitation to an in-memory diagnostic patch. Version 0.7.0.dev4 was not tested.

## Packaged dev2 quality results

The app-path suite reported 147 tests and passed, with one optional windowless-render test skipped, before the additional correction and aspect-ratio assertions described below. The live provider/import test completed. The [packaged app-path record](evidence/omlx-dev2-quality-2026-09-22/app-path.json) preserves its timings and outputs as inert JSON strings. Manual review rejected Description for inventing a “Quartz” misspelling and SVG for an incomplete table grid and a square `600 × 600` viewBox instead of the source `1200 × 680` canvas. This was a structural/value pass and a **quality failure**.

A bounded follow-up made 12 direct loopback requests: Description and SVG for three synthetic fixture types, with two prompt variants. It reused the table and generated independent prose and colored-arrow diagram PNGs with random six-digit references. Expected text and numbers appeared only in image pixels. Both variants retained the required format/content envelope, format-specific schema, temperature zero, and the same model; they did not alter the packaged server. One variant emphasized factual observations and source geometry; the other asked for a short caption and explicit vector tracing. SVG requests supplied the actual image dimensions, without fixture labels or cell values.

| Fixture | Description observations | SVG observations |
| --- | --- | --- |
| Inventory table | Factual wording still invented a Quartz spelling error. The shorter-caption variant omitted that claim in one attempt. | Dimension guidance fixed the canvas ratio, but one result had disconnected/incomplete cell borders; the other embedded forbidden HTML table elements. |
| Prose note | Both variants invented corrections absent from the source; the shorter-caption variant also called the printed text handwritten. | Text survived, but both results collapsed source positions, spacing and title/body sizes into a generic compact stack. |
| Colored-arrow diagram | Both descriptions preserved labels, colors, order and flow without an observed invented correction. | Geometry remained inaccurate; one result lost colored fills, while the other produced incorrectly formed arrowheads. |

All 12 requests completed with the requested envelope format and contained the expected text strings. That did **not** establish SVG validity or semantic fidelity. The [compact evidence](evidence/omlx-dev2-quality-2026-09-22/results.json) retains the prompt variants, output strings, timings, fixture hashes and individual manual decisions; the adjacent PNGs are entirely synthetic. No tested prompt change was adopted into production because neither variant passed across fixtures. No model download or server change was made for this comparison.

The live test now rejects invented spelling/correction claims for its known correctly spelled table fixture and requires the SVG viewBox aspect ratio to match that fixture within 1%. Invalid or zero-size viewBoxes also fail. These are fixture assertions, not production output filters. Correct aspect ratio alone does not prove faithful cell geometry, colors or arrows: manual review remains required. The hardened test was subsequently run against 32B, as recorded below. Issue `clip-cqc.11` remains unresolved; native capture/focus/paste acceptance is separate.

## Installed dev2 with the 32B model

With explicit user approval, `mlx-community/Qwen3-VL-32B-Instruct-4bit` revision `6e5644d3ea4b953b5221ffd02339bf897041038a` was downloaded into staging outside model discovery. All 19 published files, totaling **19,636,446,591 bytes (19.64 GB)**, matched their authoritative sizes and hashes before the directory was moved atomically into the model library. The four safetensors shards contain 1,958 tensors, including vision and language weights. Its published index references an obsolete 14-shard layout; the installed dev2 discovery code accepts the complete actual four-shard set, and mlx-vlm loads those files directly.

This run used the **installed, unmodified official oMLX 0.7.0.dev2** server on loopback port 8999, with mlx-vlm 0.6.3. A supported admin rescan was performed only after health was good and active, waiting and loading counts were zero. Both existing settings files and the server default remained unchanged, and 8B remained available. Smart Clipboard's saved model selection was not changed. A [tiny synthetic image probe](evidence/omlx-32b-quality-2026-09-22/load-probe.json) returned the exact image text in 6.66 seconds, including 4.75 seconds of model loading; server status confirmed 32B was loaded.

The full app test run completed with **147 passed, one failed and one skipped test** across 149 reported tests. The sole automated failure was the live SVG aspect-ratio assertion; the skip was optional windowless Settings rendering. All nine live attempts completed, including the isolated import/history/private-clipboard path. The [app-path record](evidence/omlx-32b-quality-2026-09-22/app-path.json) stores every output as inert JSON text. The [source fixture](evidence/omlx-32b-quality-2026-09-22/fixture.png), [SVG preview on white](evidence/omlx-32b-quality-2026-09-22/svg-render-white.png) and [manual review](evidence/omlx-32b-quality-2026-09-22/manual-review.json) document the remaining fidelity failures.

| Output / operation | Observed duration | Result for this synthetic fixture |
| --- | ---: | --- |
| Plain text | 4.51 s | Correct visible text and tab-separated item/quantity rows. |
| Markdown | 4.72 s | Correct table and values. |
| JSON | 5.31 s | Correct code and item/quantity associations. |
| YAML | 5.45 s | Correct title, code and item/quantity associations. |
| HTML | 19.36 s | Correct table structure and values in inspected source; no browser-render fidelity claim. |
| SVG | 27.79 s | **Automated and manual FAIL:** `400 × 300` viewBox distorts the `1200 × 680` source; extra empty row, equal-width columns and outlined text also differ visibly. |
| Description | 9.52 s | **Manual FAIL despite structural PASS:** correct values, no spelling hallucination, but falsely describes the left-aligned title and code as centered. |
| Auto detect | 6.41 s | Chose Markdown and preserved the table. |
| Import → private clipboard → history reload | 2.72 s | Correct text and isolated clipboard/history assertions passed. |

The 32B model therefore loads and works for these extraction checks, but it did **not** resolve current-prompt Description/SVG fidelity. These individual timings are not a general speed comparison. This test used synthetic images, isolated preferences/history and a private pasteboard; it did not capture the screen, register global shortcuts, open app windows, use the system clipboard, switch saved provider preferences or establish native capture/paste acceptance.

A final bounded follow-up made six direct HTTP requests: Description and SVG for the table, prose note and colored-arrow diagram, using one general prompt revision with trusted image dimensions and explicit SVG text/row guidance. All six completed with the requested format and expected text; all three SVG viewBoxes matched their source dimensions. Manual review still found an extra table row and wrong column geometry, compressed prose typography/spacing, and relocated diagram shapes and labels. Diagram arrows were useful and correctly directed, but layout fidelity remained insufficient. Description still invented a bold prose title and centered diagram labels/title; the revised table description's broader centered-layout claim was ambiguous, so it is not treated as equally strong failure evidence.

This follow-up did not establish a correction across fixtures, and no production prompt change was adopted. The table reused the exact 32B baseline image; prose and diagram had no current-prompt 32B baseline. Prompt wording, dimensions and user direction changed together, so their individual effects were not isolated. Detailed exploratory artifacts remain local; the retained baseline above is the reviewable app-path record. Further prompt probing stopped after this comparison.

## Earlier diagnostic app-path evidence

The opt-in test generates an AppKit PNG containing a random six-digit code and a two-column inventory table. Expected values appear only in the pixels sent to the model. It calls the real `ProviderClient` and oMLX adapter for seven explicit formats and Auto, then exercises imported-image conversion with a private pasteboard, in-memory preferences and an isolated history directory. No Keychain access, real screen capture, global hotkeys or app windows are used.

Live failures led to concrete request changes: native schemas now restrict explicit requests to the selected format; the prompt distinguishes plain text, prose descriptions and SVG elements; the oMLX request uses temperature zero and includes the concrete instructions alongside the image. The decoder still rejects format mismatches. The test also checks row associations and rejects repeated YAML envelopes, introduced Markdown in plain text, missing SVG text/viewBox, and HTML table elements inside SVG.

The earlier diagnostic run passed 121 automated tests, including the live integration test and windowless Settings rendering; its optimized build also passed. Those assertions establish syntax, known values and private clipboard/history behavior; they do not establish complete output quality. The preserved [summary](evidence/omlx-2026-09-22/summary.json), [synthetic fixture](evidence/omlx-2026-09-22/fixture.png), [outputs as inert JSON strings](evidence/omlx-2026-09-22/outputs.json), and [manual review](evidence/omlx-2026-09-22/manual-review.json) must be read together.

| Output / operation | Final observed duration | Review result for this fixture |
| --- | ---: | --- |
| Plain text | 1.45 s | Correct values and tab-separated rows. |
| Markdown | 1.29 s | Correct table and values. |
| JSON | 1.43 s | Valid record with correct item/quantity associations. |
| YAML | 1.27 s | Valid record with correct associations, without a repeated conversion envelope. |
| HTML | 5.36 s | Source contains the expected table rows and values; inspected without rendering. |
| SVG | 10.58 s | **Quality FAIL:** valid SVG and editable text, but extra grid lines and inaccurate table geometry. |
| Description | 2.48 s | **Quality FAIL:** correct values and prose, but invented spelling commentary about “Quartz”. |
| Auto detect | See saved summary | Selected Markdown and preserved the table. |
| Import → private clipboard → history reload | See saved summary | Copied exact returned text; preserved original image/provenance; history reopen made no provider call or clipboard write. |

These earlier timings are individual observations on one synthetic fixture, not performance guarantees or a broad accuracy benchmark. The subsequent packaged-server and multiple-fixture probes above address those two earlier evidence gaps without establishing complete quality. Text-only model failure, local/LAN authentication, cancellation during a live request, native shortcut → region/window selection → actual paste, focus/cursor recovery and signed-update acceptance require their own evidence. The earlier diagnostic did not change the installed Smart Clipboard or public v0.3.1 release; later local installation is not public-release acceptance.

## Repeating the opt-in test

Use a running, unauthenticated **loopback** server with the selected complete vision model and working structured generation. The test intentionally does not retrieve credentials. It does not start a server, download a model or apply the diagnostic patch. Set the address to the server's actual port; the example port below is oMLX's upstream default, not a discovered setting.

```sh
SMART_CLIPBOARD_OMLX_TEST_URL=http://127.0.0.1:8000/v1 \
SMART_CLIPBOARD_OMLX_TEST_MODEL=Qwen3-VL-8B-Instruct-4bit \
SMART_CLIPBOARD_OMLX_TEST_SERVER_BUILD='Enter the exact server version and any local patches' \
SMART_CLIPBOARD_OMLX_TEST_RESULTS=/tmp/smart-clipboard-local-results \
./scripts/test.sh
```

Both URL and MODEL must be set to enable live inference. The suite prints a unique artifact directory, saves the fixture/results and updates `summary.json` after each attempt. Inspect every output and record semantic/visual failures separately even when automated assertions pass. Use the native gates in [UAT.md](../UAT.md) for final acceptance; this test cannot replace them.
