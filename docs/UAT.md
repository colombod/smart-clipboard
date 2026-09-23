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
| D07 Interface languages | Launch separately in English, Italian, Spanish, French and German. Menus, settings, alerts and accessibility labels use the selected supported language. Inspect long text in light/dark appearance and at minimum window sizes. Captured text and provider/model identifiers remain unchanged. Unsupported locales fall back to English. |
| D08 Capture translation | On a Mac using a different language, capture a Spanish fixture with Keep source language, System language, and a specific target. Source remains Spanish; translated versions use the selected target, preserve visible values and copy quietly. Pass through remains the unchanged image. |
| D09 History languages and upgrade | Reopen the fixture, generate a different target language, switch between saved versions, then restart. Originals and format/language variants survive. Merely switching a saved version makes no AI request and does not change the clipboard. Upgrade old settings/history with translation directions; they remain effective until an explicit language is chosen. |

Untested configuration gates must be stated as limitations of the preview. Do not imply both connection types, login startup, multiple displays, or clean-machine installation are proven by testing one local configuration.

## Local SVG tracing preview

Preview build 14 adds **SVG method → Trace on device**, using a native VTracer helper bundled with the app. **Reconstruct with AI** remains the default. These gates describe required observations; their presence here is not evidence that they passed. Record each gate as NOT RUN until exercised, then record the exact candidate, actions and evidence under `clip-cqc.28`. The feature is published in preview build 14. [Build 14 verification](releases/v0.4.0-preview.14.md#verification-status) records the completed checks and the native capture checks not repeated on that build; publication does not mark all gates as passed.

Use public or synthetic fixtures: a photograph with a recognisable object and visible markings, a flat logo with a cut-out or transparent area, and a line drawing. Retain the input and output for visual comparison. Include the public pirate-kitten example from GitHub issue #3 to check the eye patch, markings and silhouette. Do not substitute “valid SVG” for fidelity to the source.

| Gate | Real user action | Required observation |
| --- | --- | --- |
| T01 Default and saved choices | Upgrade an isolated copy of old preferences, inspect SVG settings, then select Trace on device, a preset and Detailed. Restart. | Existing users retain Reconstruct with AI. Chosen method, preset and detail persist. No new setup prompt or automatic window appears. Non-SVG preferred formats retain their previous behavior. |
| T02 Region capture to SVG | Choose SVG, Trace on device, Photo and Balanced; close every Smart Clipboard window. Focus a destination, capture the photo with the global region shortcut, wait and paste. Repeat. | Both runs produce SVG source text representing the selected crop. The overlay and cursor help disappear. Progress ends in ready only after copying; the original app and insertion point remain usable. No settings, editor, method chooser, confirmation or Copy step appears. |
| T03 Window capture to SVG | Repeat T02 twice with the global window shortcut. Exercise Space to switch capture modes separately. | Only the selected window is traced. Selection, focus, clipboard and notification behavior meet T02. A file import cannot pass T02 or T03. |
| T04 Independent local operation | With no usable AI connection or credentials in an isolated configuration, trace all three fixtures. Exercise an offline test without changing the user's network settings. | Tracing succeeds through the bundled helper. No API, model-list, server or credential request occurs; no external package, Python runtime, model download or helper installation is required. Switching SVG back to Reconstruct with AI uses the configured AI route and retains its normal failure behavior. |
| T05 Presets, detail and fidelity | Trace the photo, logo and line drawing with their matching presets; compare Balanced and Detailed on the same originals. Save and open each SVG in an independent renderer or editor. | Outputs are valid, bounded vector SVGs, without embedded raster images, scripts or external resources. Compare silhouettes, holes, markings, crop and background against the original. Record file size and duration for each detail level. Detailed must not silently select a different preset. Document approximation limits rather than treating rendering success as faithful tracing. |
| T06 History reuse | Open a captured image in History, create a local trace, then create an AI SVG from the same original. Reopen the saved results and restart. Repeat with another preset/detail setting and a result above 128 KiB. | Original, local and AI results remain available with clear method/preset/detail labels. Saved results reopen without retracing or an AI call. Opening History never copies; Copy and Copy after manual conversion behave as configured. Results do not overwrite unrelated methods or trace configurations. Large SVGs show a ready-to-copy/save summary instead of filling the text editor; Copy and Save still retain the complete result. |
| T07 Cancellation and failure | Seed the clipboard with known text. Cancel selection; separately cancel an active trace. In a controlled test build, exercise a missing or failed helper and malformed output. Then trace successfully. | Previous clipboard contents remain on cancel or failure. Cancellation is quiet. Failure reports through menu status and the configured failure notification without opening a window. Busy state clears, a late helper result cannot copy, and the next operation succeeds. Never alter the user's installed helper to simulate failure. |
| T08 Capture settings snapshot | Start a trace, then change the selected method, preset or detail while it runs. Start a second operation afterwards. | The active trace completes with its original settings. The next operation uses the new choices. Language settings and saved directions neither translate nor modify the local trace; text is represented by outlines and the visible background is retained. |
| T09 Installed package | Install the exact signed candidate package on a clean test installation, then perform T02 with no development tools or extra runtime configured. | Bundled helper is present, signed and executable from the installed app. Tracing requires no terminal command or dependency installation. Record install/version/hash and actual native capture evidence; a development checkout run cannot pass this gate. |
| T10 Labels and announcements | Inspect new controls in all five interface languages, light/dark appearances and narrow windows; exercise keyboard navigation and VoiceOver. Enable ready/failure notifications and trace. | Method, preset, detail, action, help and error strings are translated and readable. Selection is announced and controls are reachable. Progress/outcome follows the existing quiet workflow. Notifications contain no captured image or text. Record macOS suppression separately from app delivery; do not change Focus or sharing privacy without authorization. |

These gates supplement G01–G12, distribution and accessibility acceptance. Local tracing does not establish AI SVG quality or accurate chart-data reconstruction. Any unrun gate or observed limitation must remain explicit in candidate notes.

## Accessibility gates

The user has identified accessibility as a required part of the product. [Accessibility status and acceptance](ACCESSIBILITY.md) defines A01–A06: VoiceOver setup, pointer-free region/window capture, spoken outcomes, keyboard/focus recovery, low-vision layouts and alternative input. These supplement G01–G12; native controls, labels, imports, unit tests and offscreen renders cannot establish assistive-technology acceptance. `clip-cqc.14` and `clip-cqc.15` block candidate release acceptance until native accessibility and usable text enlargement are verified. Keep the normal quiet background workflow throughout.

## Multiple-provider candidate

The development candidate adds Anthropic, Gemini, Perplexity and oMLX. It is not part of public v0.3.1. Track evidence for each exact provider/model/API or server version under Beads epic `clip-cqc`; source and fixture tests do not establish live support.

Development checks on 22 September 2026: the initial candidate passed 114 tests, an optimized build and all 10 isolated release-orchestration scenarios. Subsequent local-model work passed 121 automated tests, including opt-in live synthetic-image and windowless render tests. Manual inspection found Description and SVG quality failures despite passing automated format/value assertions; see [oMLX evidence](testing/OMLX.md). Full connection forms were inspected in light/dark mode; detached native tabs and scrolling require live UI verification. No native capture was used for this candidate's evidence. The installed app was left unchanged.

The About-page addition is in development version 0.4.0 build 8. Its app bundle built and passed signature verification, and the subsequent regression run passed 120 tests with the live oMLX test skipped. About and third-party notices were inspected in windowless light/dark renders using the actual bundle's version, icon and notices. Native tab selection, sheet dismissal and menu interaction still require live UI verification; no application window was opened for these checks. This build is not a new signed/notarized public release.

The accessibility foundation update is in development version 0.4.0 build 9. It adds explicit labels/selected states, safe VoiceOver announcement requests, recorder navigation/lifecycle cleanup, Command-W, resizable Settings and scrolling sidebar/About content. The optimized build/signature verification and 134 tests passed; one opt-in live AI test was skipped. App-state announcement integration used mock providers and a private clipboard. Offscreen inspection found and corrected white-on-light-green prominent buttons in dark mode. High-contrast named-appearance snapshots still used the normal palette and are not proof of system Increase Contrast support. The installed app and macOS accessibility settings were not changed; A01–A06 remain NOT RUN.

Later on 22 September, signed/notarized **0.4.0 build 10** was installed locally as a private bootstrap, preserving preferences/history and selecting the existing 8B local model on the official packaged oMLX 0.7.0.dev2 server. The native Connection test passed. Renewed Screen Recording approval required clearing only the obsolete ad-hoc app entry and adding the installed signed app after user authorization; the warning then cleared. Native capture-to-paste acceptance is still pending. Both 8B and the newly downloaded 32B model pass useful synthetic extraction checks but fail Description/SVG fidelity; [the current evidence](testing/OMLX.md) records those failures. The updater's private installation test and native accessibility acceptance remain open. No 0.4 release was public at that stage. Later preview publication must keep these limitations explicit and does not retroactively pass unverified gates.

### Installed build 11: notification and updater checks

The final signed/notarized **0.4.0 build 11** was built from commit `8d195552c5363672d26c929837f66ac60c46679a`. Its final offline regression reported **177 passed and two opt-in tests skipped**, across 111 application tests and 68 core tests (179 total). Live oMLX and windowless rendering were the opt-in skips; they are not counted as passes. Later documentation-only corrections do not change that binary, source revision or prepared signed assets.

The user confirmed both native **ready** and **failure** banners and their sounds on the installed final app. Earlier missing alerts were traced to macOS suppression: first the policy for shared/recorded displays, then an active Sleep Focus. With the user's explicit approval, those settings were temporarily adjusted for the check. The sharing policy was then restored to **Notifications Off** and verified in System Settings; the user confirmed Sleep Focus was restored. This verifies visible/audible delivery when macOS permits it, not an ability to bypass Focus or screen-sharing privacy policy. Notification-click behavior and every wider capture gate are not implied by this result.

In the private Sparkle updater rehearsal, the installed app rejected a modified feed and a modified archive, then successfully installed signed/notarized build 11 over build 10. The installed bundle matched the prepared candidate, and existing preferences/history were preserved. This is evidence for that upgrade path; it does not substitute for verifying a published download on a clean installation under D06.

These are bounded preview results, not full accessibility, cloud-provider, native capture-matrix or Description/SVG quality acceptance. The local-model failures and unverified gates remain explicit. An optional demo recording did not show the intended capture-to-paste sequence, so no demo is published or promised; a future synthetic recording remains deferred under `clip-bkc.16`.

| Connection | Live candidate status | Additional evidence required |
| --- | --- | --- |
| OpenAI API | Not yet rerun on this candidate | Existing-key migration, synthetic image test, G03/G04/G05/G07/G09/G11. |
| ChatGPT via Codex | Unverified on this candidate | Actual ChatGPT login and image execution through supported CLI; preserve noninteractive background failure behavior. |
| Anthropic | Unverified | Available vision/schema model, account access, complete-response parsing and no tools. |
| Google Gemini | Unverified | Available model/project, Interactions image/schema request, optional storage disabled and no tools. |
| Perplexity | Unverified | Explicit direct vision model, no presets/web search/tools/fallback list, schema cold-start behavior. |
| oMLX | Synthetic conversion/private clipboard/history checks exercised complete Qwen3-VL 8B/32B models on the unmodified official oMLX 0.7.0.dev2 package; useful extraction works, while Description/SVG fidelity fails | Resolve output quality; complete native G03/G04/G05/G07/G09/G11 evidence, model fallback disabled, offline processing and local/LAN authentication. |

For every advertised connection, run G03 and G04 twice consecutively on the exact candidate with app windows closed. Record actual paste content and type, focus and cursor recovery, model/account/server version, output validity and cold/warm duration. Do not put private screenshots or credentials in the evidence record.

Additional regression cases: switch provider/model/address while selecting or converting and confirm the initial configuration is used; change a key or endpoint and confirm readiness is invalidated and keys are not sent to another destination; restore an unreadable configuration and confirm captures do not fall back to OpenAI; cancel a delayed request and confirm its late response does not copy; retry a history image with another provider and verify provenance even when output text is identical. Pass through must perform no model-list request, key lookup or AI call.

Check invalid/revoked keys, unavailable models/server, local text-only model, oversized input, refusal, incomplete output, invalid JSON/YAML, rate/quota error, redirect and timeout. Each must preserve the clipboard, avoid app/credential windows, terminate busy state and allow a subsequent successful capture. Use the existing G01–G12/D01–D06 gates for install/startup/appearance/history and signed release acceptance.

## Fixtures and evidence

Use synthetic/public content: a short sentence with a unique number, a two-column three-row table, a small record with string/number/boolean values, and a simple labelled diagram. Keep the complete fixture within the selected crop. Verify known values and paste type, not only the app's success label.

For G03/G04, evidence must cover the selection, the destination after actual Command-V, and whether the app appeared or stole focus. Do not inject expected output into the clipboard or target document. If automation cannot operate the native selector, a person performs the drag/window click; record that assistance and verify the remaining flow. Never substitute an import and mark these gates PASS.
