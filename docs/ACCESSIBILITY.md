# Accessibility status and acceptance

**Status: partial support; end-to-end accessibility is not yet accepted.** This assessment covers development version **0.4.0 build 9**, not the public v0.3.1 download. Native controls provide a useful foundation, but they do not establish that a blind user or someone who cannot use a pointer can complete the capture workflow.

The [22 September native execution record](testing/ACCESSIBILITY-NATIVE.md) is **BLOCKED**: the signed UI runner did not reach test execution, so there is no automated accessibility audit result. Limited live label and Settings keyboard observations are recorded separately and do not pass A01 or A04; A02, A03, A05 and A06 were not run.

The essential experience remains **configure once → invoke capture → select the source → hear/read completion → paste into the original app**. Accessibility must not require an editor or Settings window after every capture. Ordinary startup, conversion, cancellation and failure must not open an app window or steal focus.

## Implemented foundation

| Area | Current behavior | Evidence and limits |
| --- | --- | --- |
| Control names | Close clip, dismiss error, shortcut recorders, original image and result editor have explicit labels. History Open/Delete actions identify their capture and date. Decorative images are hidden from accessibility. | Source reviewed; actual VoiceOver reading order and navigation remain unverified. The original image label identifies its role; it is not an image description. |
| Selected format and state | Selected formats have a checkmark and selected accessibility trait. The menu-bar button exposes a text status/value. Failures include explanatory text when the menu/editor is opened. | Does not depend only on a green/red change. Native accessibility-tree inspection remains required. |
| Spoken progress | With VoiceOver running, the app requests brief selection, processing, copied, cancelled and failure announcements. Copy completion names the resulting format and says it is ready to paste. | Tests exercise transition handling and exclude private content. Delivery, interruptions, timing and background-app behavior require real VoiceOver tests. Captured text, output, filenames and raw provider errors are not automatically announced. |
| Keyboard controls | Native controls and configurable global shortcuts; Command-W closes the current app window. The recorder lets Escape cancel and Tab/arrow navigation leave recording. Control-Option commands pass through when VoiceOver is enabled. Recording ends when its window loses key status or the app deactivates. | Recorder policy tests pass; native focus, tab order, window lifecycle and Full Keyboard Access are separate gates. Caps Lock VoiceOver commands and existing user-defined shortcut conflicts remain unverified. Automatic alternative shortcuts avoid Control-Option combinations. |
| Appearance/layout | Native text/background colors, light/dark accent variants, darker prominent-button fills for white text, resizable Settings, scrolling sidebar and About content. | Synthetic offscreen images support limited visual inspection. Offscreen native tabs are incomplete. Named high-contrast NSAppearance snapshots still resolved the normal palette, so they do **not** prove Increase Contrast support. |

The audit and foundational fixes are tracked in Beads `clip-cqc.13`. They do not close the native accessibility gates.

## Important gaps

**Pointer-free capture is unproven.** Smart Clipboard delegates rectangle/window selection to macOS's interactive screenshot selector. A keyboard shortcut starts that selector; that alone does not make source selection keyboard-accessible. Apple's screenshot instructions describe pointer selection. We must demonstrate an accessible complete flow or provide an equivalent accessible capture route. Importing an image is useful, but does not satisfy this requirement.

**Text enlargement is incomplete.** Several headings and captions use fixed small sizes; there is no app-wide text-size setting. Resizing the window does not enlarge text. SwiftUI Dynamic Type sizes do not change text size on macOS, so applying an iOS-style Dynamic Type override is not sufficient evidence. Low-vision layout and genuine text enlargement are tracked separately in `clip-cqc.15`.

**Assistive technologies need real acceptance testing.** The native session attempted VoiceOver and Full Keyboard Access, but established neither spoken/navigation acceptance nor complete keyboard traversal. Voice Control, Switch Control, Zoom and live contrast acceptance remain untested. Focus restoration after capture, failure, sheet dismissal, deleting history and cancelling recording remains unverified. Native testing and any required capture alternatives are tracked in `clip-cqc.14`. Both issues block candidate release acceptance (`clip-cqc.9`). There is no accessibility certification or conformance claim.

## Required native gates

These are acceptance criteria, not execution results or a task list. Record PASS, FAIL, BLOCKED or NOT RUN and evidence in Beads. Identify the exact app binary/version, macOS version, assistive settings, synthetic fixture, actions, assistance and observed result. NOT RUN and BLOCKED cannot count as a pass.

| Gate | Required observation |
| --- | --- |
| A01 Discover and configure | With VoiceOver and keyboard navigation enabled in the test session, find the menu-bar item, read readiness, open Settings, reach every tab and configure connection/preferred output/shortcuts. Labels and values identify controls; focus order is predictable; no unlabeled essential controls. Close with Command-W and return to the original app. |
| A02 Capture without a pointer | With app windows closed, complete region and window capture without mouse/trackpad or sighted assistance; paste the actual selected content into the original app. Run each twice. Verify selection switching, Escape, cursor cleanup and focus/insertion-point recovery. An import or a shortcut followed by someone else dragging cannot pass. |
| A03 Hear operation outcomes | Exercise pass through, AI conversion, repeat capture, manual conversion without auto-copy, selection/conversion cancellation, failure and recovery. VoiceOver delivers useful non-duplicate progress/outcomes without speaking the capture or stealing focus. Failure guidance leads to the visible error. Failed/cancelled operations preserve the clipboard. |
| A04 Navigate and recover focus | Traverse Settings, all provider forms, result editing, history and About/notices by keyboard and VoiceOver. Test both VoiceOver modifiers, shortcut recorder Tab/Shift-Tab/Escape/close/deactivation, sheet dismissal, row deletion and scrolling. No trap or paused global capture handler remains. |
| A05 Low vision | Use actual supported text enlargement and system Zoom; inspect minimum/expanded windows and long labels/errors. No essential content is clipped or unreachable. Verify live light/dark, Increase Contrast and Reduce Transparency, including focus indicators and text/button contrast. Test rendered text, not only an enlarged window. |
| A06 Alternative input and motion | Use Voice Control and Switch Control to discover and activate essential controls and complete the supported capture route. Respect Reduce Motion; essential status cannot depend on animation. Record any selector limitation explicitly. |

Native gates supplement [the ordinary capture and release gates](UAT.md); neither replaces the other. Use synthetic captures and isolated history/clipboard fixtures. Do not toggle a person's accessibility settings, launch visible test windows or run speaking tests unexpectedly during unrelated work.

## Reproducing supporting checks

During the earlier windowless checks on 22 September 2026, on macOS 26.7 (25G229), the optimized build and app-signature verification succeeded. The regression run passed **134 tests**, with one opt-in live AI test skipped. This includes real AppModel publisher integration checks using mock providers, an injected announcement collector, private clipboard and isolated history; no actual speech or native screen selection was tested. Synthetic editor/history/About and expanded Settings snapshots were inspected for layout and button legibility. Those supporting checks did not replace the installed app, open an app window or change a macOS accessibility setting. The later authorized native session and its settings restoration are documented in the [separate execution record](testing/ACCESSIBILITY-NATIVE.md).

The unit and integration tests run with `./scripts/test.sh`. Set `SMART_CLIPBOARD_RENDER_DIR` to an empty temporary directory for opt-in windowless snapshots, and `SMART_CLIPBOARD_ABOUT_BUNDLE` to a built app bundle to verify its actual About resources. Live AI tests stay opt-in and are not required for the accessibility policy checks. The render host is never attached to a window; these images cannot validate the live accessibility tree or native focus.

Primary references: [Apple accessibility design guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Mac keyboard navigation](https://support.apple.com/en-us/102650), [VoiceOver modifier settings](https://support.apple.com/en-ie/guide/voiceover/cpvokys01/mac), [native screenshot selection](https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac), [SwiftUI Dynamic Type platform behavior](https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize), and [AppKit accessibility announcements](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested).
