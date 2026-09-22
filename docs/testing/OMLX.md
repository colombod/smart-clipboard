# Local vision test evidence — 22 September 2026

The downloaded `mlx-community/Qwen3-VL-8B-Instruct-4bit` can read images and produce structured results. **This configuration is not accepted for all output formats or for the native capture workflow.** The final automated checks passed, but manual review found Description and SVG quality failures.

## Environment and server compatibility

Tests used an M5 Max Mac with 128 GiB memory, macOS 26.7 (25G229), the multiple-provider development candidate, and the complete Qwen3-VL-8B-Instruct-4bit checkpoint. The installed oMLX app is 0.6.4, with mlx-vlm 0.6.3 and MLX 0.32.0.

The user's running server on port 8999 extracted a generated screenshot exactly in 3.74 seconds, including a random reference visible only in the image. The same image with a required JSON envelope failed: repeated/corrupted text, an unfinished response, and `finish_reason: length`. Smart Clipboard rejects this incomplete result.

This reproduced the upstream VLM grammar bug in [issue #3550](https://github.com/jundot/omlx/issues/3550). A separate loopback process on port 9000 applied the tokenizer resolver from [PR #3551](https://github.com/jundot/omlx/pull/3551), commit `ae04a79233dedccd32c0781aa172d1faf8d2b438`, **in memory**. The process used isolated settings/cache directories and was stopped after testing. No installed oMLX files or user settings were patched. The same structured probe then completed with exact extracted text in 5.67 seconds, including cold model loading.

[oMLX 0.7.0.dev2](https://github.com/jundot/omlx/releases/tag/v0.7.0.dev2) lists this fix, but it is a prerelease. Neither that packaged build nor 0.7.0.dev4 was installed or tested here. A passing diagnostic with an isolated patched process does not establish support for an untested packaged release.

## What the app-path test established

The opt-in test generates an AppKit PNG containing a random six-digit code and a two-column inventory table. Expected values appear only in the pixels sent to the model. It calls the real `ProviderClient` and oMLX adapter for seven explicit formats and Auto, then exercises imported-image conversion with a private pasteboard, in-memory preferences and an isolated history directory. No Keychain access, real screen capture, global hotkeys or app windows are used.

Live failures led to concrete request changes: native schemas now restrict explicit requests to the selected format; the prompt distinguishes plain text, prose descriptions and SVG elements; the oMLX request uses temperature zero and includes the concrete instructions alongside the image. The decoder still rejects format mismatches. The test also checks row associations and rejects repeated YAML envelopes, introduced Markdown in plain text, missing SVG text/viewBox, and HTML table elements inside SVG.

The final test run passed 121 automated tests, including the live integration test and windowless Settings rendering; the optimized build also passed. Those assertions establish syntax, known values and private clipboard/history behavior; they do not establish complete output quality. The preserved [summary](evidence/omlx-2026-09-22/summary.json), [synthetic fixture](evidence/omlx-2026-09-22/fixture.png), [outputs as inert JSON strings](evidence/omlx-2026-09-22/outputs.json), and [manual review](evidence/omlx-2026-09-22/manual-review.json) must be read together.

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

These are individual observations on one synthetic fixture, not performance guarantees or a broad accuracy benchmark. Text-only model failure, local/LAN authentication, cancellation during a live request, multiple fixture types and the exact packaged fixed server still require acceptance evidence. Native shortcut → region/window selection → actual paste, focus/cursor recovery and signed-update acceptance remain unverified for this candidate. The working installed Smart Clipboard and public v0.3.1 release were left unchanged.

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
