# User experience and release acceptance

## The experience

Smart Clipboard is a background capture-to-clipboard utility. The everyday interaction is:

**Configure once → press a global shortcut → select a rectangle or window → wait for the menu-bar completion indicator → paste into the app already in use.**

There is no required editor, format picker, Convert button, Copy button, or confirmation between selection and paste. Smart Clipboard must not open a window or take focus on startup, capture completion, or failure. The native macOS selection overlay is expected after a capture command. Initial OS permission and explicitly requested connection setup may require system dialogs; these are setup steps, not the everyday workflow.

Settings, history, and the optional editor appear only after an explicit request. Every app window can be closed normally without quitting the menu-bar utility. Closing Settings must not freeze or wait for a Keychain operation.

## Saved preferences

The preferred-format list contains **Auto detect**, **Pass through (image)**, **Description**, **Plain text**, **Markdown**, **HTML**, **SVG**, **JSON**, and **YAML**. An optional default direction applies to new AI conversions. Preferences and global shortcuts survive app restart.

- **Auto detect:** AI selects an appropriate editable format from the source. The resolved format and result are kept in history.
- **Pass through (image):** copy the selected screenshot as an image, without OCR, AI, extraction, or a network dependency.
- **Explicit format:** use the chosen format without asking again. Markup and structured output paste as source text; image output pastes as an image.

History retains the original capture so another format can be generated later. The user controls retention and can delete individual entries or clear history.

## Gate rules

These are acceptance criteria, not a task checklist. Record execution status and evidence in Beads (`clip-a41` and linked defects), not in this document.

Each run must identify the installed app version and binary hash, macOS version, connection type, preferred format, shortcut, fixture, exact actions, observed result, and any required user assistance. Use PASS, FAIL, BLOCKED, or NOT RUN. BLOCKED and NOT RUN do not pass a gate.

An automated test is supporting evidence only. Importing an existing screenshot can prove conversion and clipboard behavior, but cannot prove native selection, global shortcuts, focus preservation, or absence of unsolicited windows. Earlier-build evidence cannot establish that the current installed binary passes a scenario. Do not label the experience fully working or accepted while a required gate remains unverified.

## Core acceptance gates

| Gate | Real user action | Required observation |
| --- | --- | --- |
| G01 Quiet launch | Launch the installed app after setup, then launch it again while running. | Exactly one process and one menu-bar item. Cold startup has no app window or Dock icon. An explicit reopen may show the editor; login launch must stay silent. |
| G02 Configure once | Set a preferred format, direction and available shortcuts; close Settings and restart. | All values persist. Settings remains responsive and closes normally. No saved-key read is triggered just by opening Settings. |
| G03 Region to paste | Focus a blank target document. With a known on-screen fixture visible, press the configured global region shortcut, drag the region, wait, then press Command-V. | One capture. Correct selected content is converted and pasted in the preferred format. The selection overlay, crosshair and drag-to-capture help disappear after selection; normal pointer and input behavior resume before pasting. No Smart Clipboard window, extra click, confirmation, or app switch is required. The original target retains/recovers focus and its insertion point. |
| G04 Window to paste | Repeat G03 using the configured window shortcut and select one window. | Only that window is captured. Automatic conversion and paste behave as in G03. Test region/window switching with Space separately. |
| G05 Auto detect | Repeat G03 for a prose fixture, a formatted document/table, and a structured record. | Each result uses a source-appropriate format and contains the fixture's required values. The resolved format appears in history. No format chooser opens. Do not require identical model wording across runs. |
| G06 Pass through | Select Pass through; perform both region and window capture, including without an AI connection. Paste into a rich-text document. | Image attachment contains the selected pixels. No text extraction, AI call or credential prompt. No app window opens. |
| G07 Explicit outputs | Capture suitable fixtures once for each explicit output format. | Clipboard contains the requested format and known source values. JSON parses; YAML parses; HTML/SVG remain inert text and have the expected structure. Description accurately describes visible content. No silent fallback to another format. |
| G08 Cancellation | Seed the clipboard with known text. Escape the selection; separately cancel an active conversion from the menu. Then make a successful capture. | Cancellation preserves clipboard content, ends promptly and allows the next capture. Selection cancellation adds no history entry. Cancelling conversion keeps the original for retry. No failure window or stuck busy state. |
| G09 Failure and recovery | Exercise unavailable credentials, denied screen access and a controlled failed/offline conversion using a test configuration. Restore the connection and retry. | Clipboard is preserved. Menu-bar error is visible and actionable when opened. No automatic Settings/editor/Keychain window or indefinite busy state. A subsequent capture succeeds. Explicit OS permission setup remains available. |
| G10 Shortcut conflicts | Attempt a macOS-reserved shortcut, a duplicate capture binding and a binding registered by a test helper; then choose an available binding. | Conflict is explained at configuration time. Existing working binding remains usable. New binding works from another app. Closing settings restores recording-paused handlers. |
| G11 History reuse | After G03, explicitly open History, select that capture, request another format, then reopen the first saved result. Restart and repeat. | Original remains available; each result is associated with its format. Saved results reopen without a new AI call. Merely opening history does not overwrite the clipboard. |
| G12 Retention | In an isolated test history, exceed a small configured limit; delete one item, clear history, then set retention to zero. | Oldest originals/results are evicted together. Deletion/clear remove intended local data. Zero saves no new history. Exported files and clipboard are unaffected. Never delete the user's real history for testing. |

G01–G12 must pass on the exact candidate before claiming the core experience is accepted. G03 and G04 must each succeed twice consecutively, including one run with all Smart Clipboard windows closed. Copy/Convert buttons are forbidden in these runs.

## Distribution and configuration gates

| Gate | Required observation |
| --- | --- |
| D01 API connection | G03 passes with an API key saved through Settings. Background access is noninteractive; explicit authorization remains responsive. No credentials appear in logs, history or source. |
| D02 ChatGPT connection | G03 passes with the supported official Codex CLI ChatGPT session; no API key is required and no unintended fallback occurs. |
| D03 Login item | Enable launch at login in the installed app, perform an actual login, and verify one quiet menu-bar instance with working shortcuts. Disable it and verify persistence. |
| D04 Appearance | Settings, history, editor and menu icon remain legible in system light/dark modes; changing system appearance updates them. |
| D05 Displays | Repeat region and window capture on the second display and with differing display scale factors. Verify crop bounds and original image. |
| D06 Install/update | Download the published artifact into a clean test installation. Verify version/checksum, install, initial approval, launch and capture. Update an existing installation and record permission continuity or the exact recovery needed. Ad-hoc approval recovery is a documented preview limitation, not a pass for seamless updates. |

Untested configuration gates must be stated as limitations of the preview. Do not imply both connection types, login startup, multiple displays, or clean-machine installation are proven by testing one local configuration.

## Multiple-provider candidate

The development candidate adds Anthropic, Gemini, Perplexity and oMLX. It is not part of public v0.3.1. Track evidence for each exact provider/model/API or server version under Beads epic `clip-cqc`; source and fixture tests do not establish live support.

Development checks on 22 September 2026: the initial candidate passed 114 tests, an optimized build and all 10 isolated release-orchestration scenarios. Subsequent local-model work passed 121 automated tests, including opt-in live synthetic-image and windowless render tests. Manual inspection found Description and SVG quality failures despite passing automated format/value assertions; see [oMLX evidence](testing/OMLX.md). Full connection forms were inspected in light/dark mode; detached native tabs and scrolling require live UI verification. No native capture was used for this candidate's evidence. The installed app was left unchanged.

| Connection | Live candidate status | Additional evidence required |
| --- | --- | --- |
| OpenAI API | Not yet rerun on this candidate | Existing-key migration, synthetic image test, G03/G04/G05/G07/G09/G11. |
| ChatGPT via Codex | Unverified on this candidate | Actual ChatGPT login and image execution through supported CLI; preserve noninteractive background failure behavior. |
| Anthropic | Unverified | Available vision/schema model, account access, complete-response parsing and no tools. |
| Google Gemini | Unverified | Available model/project, Interactions image/schema request, optional storage disabled and no tools. |
| Perplexity | Unverified | Explicit direct vision model, no presets/web search/tools/fallback list, schema cold-start behavior. |
| oMLX | Synthetic conversion/private clipboard/history checks pass with a complete Qwen3-VL-8B model and temporary upstream grammar fix; Description/SVG quality fails manual review | Resolve output quality, verify a packaged fixed server, native G03/G04/G05/G07/G09/G11, model fallback disabled, offline processing and local/LAN authentication. |

For every advertised connection, run G03 and G04 twice consecutively on the exact candidate with app windows closed. Record actual paste content and type, focus and cursor recovery, model/account/server version, output validity and cold/warm duration. Do not put private screenshots or credentials in the evidence record.

Additional regression cases: switch provider/model/address while selecting or converting and confirm the initial configuration is used; change a key or endpoint and confirm readiness is invalidated and keys are not sent to another destination; restore an unreadable configuration and confirm captures do not fall back to OpenAI; cancel a delayed request and confirm its late response does not copy; retry a history image with another provider and verify provenance even when output text is identical. Pass through must perform no model-list request, key lookup or AI call.

Check invalid/revoked keys, unavailable models/server, local text-only model, oversized input, refusal, incomplete output, invalid JSON/YAML, rate/quota error, redirect and timeout. Each must preserve the clipboard, avoid app/credential windows, terminate busy state and allow a subsequent successful capture. Use the existing G01–G12/D01–D06 gates for install/startup/appearance/history and signed release acceptance.

## Fixtures and evidence

Use synthetic/public content: a short sentence with a unique number, a two-column three-row table, a small record with string/number/boolean values, and a simple labelled diagram. Keep the complete fixture within the selected crop. Verify known values and paste type, not only the app's success label.

For G03/G04, evidence must cover the selection, the destination after actual Command-V, and whether the app appeared or stole focus. Do not inject expected output into the clipboard or target document. If automation cannot operate the native selector, a person performs the drag/window click; record that assistance and verify the remaining flow. Never substitute an import and mark these gates PASS.
