# Native accessibility execution record

**22 September 2026 — FAIL. Native test access works; accessibility acceptance remains open.** The final full run executed **16 tests, with 1 passed, 15 failed and 0 skipped**. Quiet startup and Settings navigation passed. All fifteen screen audits completed across that run and a focused retry of two audit timeouts; every screen audit retained findings. The rerun verified the new window-root and history-limit labels. Earlier permission-blocked status is superseded by actual native execution.

## Candidate and isolation

| Item | Recorded value |
| --- | --- |
| macOS | 26.7 (25G229) |
| Xcode | 27.0 (27A266a) |
| Candidate | Smart Clipboard 0.4.0 build 9, separate synthetic audit build |
| Bundle identifier | `com.smartclipboard.accessibility-audit` |
| Full-baseline audit executable SHA-256 | `2e59d2546b231a47328815346da6865453b4ae6172eb355abce35308067defa1` |
| Focused About label-check executable SHA-256 | `6bbc062816df62ffd6491a774ac5ec57dc40b8befde849a7a9f7d07b6af00335` |
| Final full run and timeout-retry executable SHA-256 | `6a520069e640b29ac546cda377792c42c0d9180dfb445f626ec9b2f6c0ee27ee` |
| Installed executable SHA-256, unchanged | `d4cdbd7ef66a9d3d57e716ac7c1c5d9febe0209c125c6098eed9756c3c9026e1` |

The app was built with `ACCESSIBILITY_AUDIT`, using production views and AppModel with in-memory app preferences, temporary history, a private AppModel pasteboard, synthetic image/result fixtures, mock conversion and no global hotkey registration. It used no real screen capture, provider request or clipboard action. The installed production app was not replaced. Native editor Cut, Copy and Paste still route to the general clipboard; those commands were not exercised.

See the [runner instructions](../../Tests/AccessibilityUITests/README.md) for separate app/runner builds, all six provider form routes and evidence export. The audit app and corrected runner use local ad-hoc signing, not Developer ID or private signing keys.

## Earlier native runner attempts

| Attempt/check | Observed result |
| --- | --- |
| Xcode UI runner build | Built successfully. This proves the runner compiled, not that an audit ran. |
| First launch, unsigned runner | Failed or hung before test execution. No audit findings were produced. |
| Corrected runner signature | `codesign --verify --deep --strict` passed after local ad-hoc signing. |
| Second launch, signed runner | Still stalled before test execution; the observed runner remained at `_dyld_start` with a 96K footprint. No test method or accessibility audit result was observed. |
| Permission evidence | Logs recorded a Developer Tools denial for `com.openai.codex`, and permission was requested from the user. The later user-requested retry succeeded without us changing Developer Tools permission; its Settings list still showed only Terminal, off. The earlier denial is not an established cause of the stall. |
| Accessibility Inspector alternative | The Inspector target list omitted the menu-bar audit app (`LSUIElement`). No Inspector GUI audit ran. |

A successful build and valid signature cannot substitute for executing the tests. These earlier attempts produced no audit result; the executed retry below supersedes their BLOCKED status.

The completed 16-case runner compiled successfully without launching UI. The normal optimized app build and signature verification also passed. The ordinary regression suite passed 133 checks; two opt-in checks (windowless rendering and live AI) were skipped. These results verify build/regression behavior, not native accessibility acceptance. The isolated app and both test runners were stopped after the attempt.

Audit-tooling checks confirmed that the launch preparation rejects the installed production app and accepts only the isolated audit bundle. The completion validator passed 14 synthetic result fixtures plus source/identity edge checks, and rejected the actual interrupted native result. Those fixtures test reporting safeguards; they are not native app test executions.

## Executed native audits and follow-up

| Run/check | Result and limits |
| --- | --- |
| First completed About audit | Four findings: three missing descriptions (the Settings hosting root, the selected About content group and Touch Bar), plus a parent/child mismatch under the native window zoom button. |
| Full baseline | 16 executed, 1 passed, 15 failed, 0 skipped. Quiet startup, opening Settings with Command-comma, selecting its actual tabs and closing it with Command-W passed. Tab selection in this automated test uses native controls; it does not establish full keyboard-only or VoiceOver traversal. |
| Screen-audit coverage | 12 of 15 screen audits completed. Empty editor, empty history and General Settings failed their readiness locator before calling the audit because macOS exposed the expected static text through `value`. This was a harness lookup defect, not evidence that the text was absent. |
| Corrected locator | The readiness guard checks static-text `value` and control `label`. The final run reached all fifteen audits, including the previously missed empty editor, empty history and General Settings. |
| Focused About label check | Labeling the Settings hosting root removed its missing-description finding: four findings became three. The tab's `.contain` label appeared on its scroll view, while the unnamed native tab-content group remained. The audit still failed. |
| Final full run | 16 executed, 1 passed, 15 failed, 0 skipped. Thirteen screen audits completed; populated History and Shortcuts hit the native audit timeout. All readiness checks succeeded. |
| Focused timeout retry | The same binary and runner completed both populated History and Shortcuts audits. They retained four and five findings respectively; neither timed out again. |
| Verified description fixes | Settings, editor and history hosting roots expose their new labels; their missing-description findings are removed. The history-limit field exposes “Maximum saved clips,” and its missing-title finding is removed. Child controls remain present, and the native Settings navigation/close test still passes. |

Remaining findings include missing actions for the visible Provider popup and Saved formats menu, an unnamed outer history-row element, and contrast reports. All twelve Settings contrast flags in the initial completed reports were below the scroll viewport; those elements must be scrolled into view and checked again. Three editor/history contrast flags were visible and need separate measured verification. Neither apparent legibility nor an off-viewport flag is a reason to suppress a finding. The native tab-content group, Touch Bar description and zoom-button parent/child findings also remain recorded; compare framework-generated nodes with a minimal native app before attributing them to macOS. No findings were suppressed or excluded, and OS-owned controls were not altered to remove them. Follow-up is tracked in `clip-cqc.17`.

After the label fixes, the normal regression suite again passed 133 checks with two opt-in checks skipped, and the optimized production build and signature verification passed. The installed app hash stayed unchanged. Process inspection confirmed the isolated app and native test runners exited after the final retry.

Raw `.xcresult` bundles, audit JSON, accessibility trees and screenshots remain outside Git. Local evidence directories are:

| Evidence | Local directory |
| --- | --- |
| First completed About retry | `/tmp/smart-clipboard-accessibility-access-retry-20260922` |
| Full baseline | `/tmp/smart-clipboard-accessibility-native-full-20260922` |
| Focused About label check | `/tmp/smart-clipboard-accessibility-labels-about` |
| Final full rerun | `/tmp/smart-clipboard-accessibility-native-verified-20260922` |
| Focused timeout retry | `/tmp/smart-clipboard-accessibility-native-timeout-retry.xcresult` and `/tmp/smart-clipboard-accessibility-native-timeout-attachments` |

The candidate hashes come from the runs' `audit-app.json` records; the timeout retry reused the final full run's test configuration and binary. Raw trees and screenshots can include unrelated native menu or desktop information and are not reproduced in this report.

## Limited live observations

Computer-use inspection exposed accessibility labels in the actual editor and General Settings window. Command-comma opened Settings, and Command-W closed it. These observations do not verify the full reading order, every provider form, all keyboard paths or return to the original app's insertion point.

Tab focused the General Settings **Default direction** control. Subsequent Tab and Shift-Tab attempts did not reach other controls during an attempted Accessibility Inspector Full Keyboard Access toggle. This is an incomplete navigation observation, not proof that keyboard traversal works or a complete diagnosis of a focus trap.

VoiceOver was switched on in System Settings for the test. The computer-use tool stalled while attempting to inspect VoiceOver. No spoken announcement or VoiceOver navigation result was verified. System Settings later confirmed VoiceOver was off again.

## Accessibility settings and restoration

| Setting | Baseline, attempted change and final observation |
| --- | --- |
| VoiceOver | Off → on for the test → off confirmed in System Settings. No verified speech/navigation result. |
| Full Keyboard Access | Recorded value changed 0 → 1 for the attempt, then restored to 0. Effective complete keyboard navigation was not established. |
| Accessibility Inspector toggles | All six accessibility toggles were off at baseline and off at the final check. |
| VoiceOver caption panel | Already enabled at 22 pt before the session; left unchanged. |

No real capture, provider or clipboard operation was performed. The observations above must not be extended into claims about those workflows.

## Acceptance gates

The gate definitions and release blockers remain in [Accessibility status and acceptance](../ACCESSIBILITY.md). “Partial observation” is not PASS.

| Gate | This session's status | Limit |
| --- | --- | --- |
| A01 Discover and configure | Partial observations; **not PASS** | Automated quiet startup and Settings open/tab selection/close passed; VoiceOver discovery, all configuration controls and focus return not verified. |
| A02 Capture without a pointer | **NOT RUN** | No native capture or paste. |
| A03 Hear operation outcomes | **NOT RUN** | No verified live announcements or operation outcomes. |
| A04 Navigate and recover focus | Partial observations; **not PASS** | Actual Settings tab selection and close passed, and screen audits reported findings; complete keyboard/VoiceOver traversal, modifiers and focus recovery remain unverified. |
| A05 Low vision | **NOT RUN** | No completed low-vision evaluation. Inspector toggle checks do not establish contrast, enlargement or Zoom acceptance. |
| A06 Alternative input and motion | **NOT RUN** | Voice Control, Switch Control and Reduce Motion acceptance not exercised. |

Native accessibility is not accepted under `clip-cqc.14`, with executed audit findings tracked in `clip-cqc.17`; text enlargement remains open under `clip-cqc.15`. These continue to block candidate release acceptance (`clip-cqc.9`). The current native audit status is FAIL, not permission-blocked. This record does not change the project's partial-support status or claim accessibility conformance.
