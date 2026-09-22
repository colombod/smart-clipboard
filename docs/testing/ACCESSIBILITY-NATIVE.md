# Native accessibility execution record

**22 September 2026 — BLOCKED. No native accessibility acceptance pass.** The XCTest runner built, but neither launch attempt reached the test methods. There is no `performAccessibilityAudit` result. Separate computer-use observations establish only the limited behaviors recorded below.

## Candidate and isolation

| Item | Recorded value |
| --- | --- |
| macOS | 26.7 (25G229) |
| Xcode | 27.0 (27A266a) |
| Candidate | Smart Clipboard 0.4.0 build 9, separate synthetic audit build |
| Bundle identifier | `com.smartclipboard.accessibility-audit` |
| Audit executable SHA-256 | `2e59d2546b231a47328815346da6865453b4ae6172eb355abce35308067defa1` |
| Installed executable SHA-256, unchanged | `d4cdbd7ef66a9d3d57e716ac7c1c5d9febe0209c125c6098eed9756c3c9026e1` |

The app was built with `ACCESSIBILITY_AUDIT`, using production views and AppModel with in-memory app preferences, temporary history, a private AppModel pasteboard, synthetic image/result fixtures, mock conversion and no global hotkey registration. It used no real screen capture, provider request or clipboard action. The installed production app was not replaced. Native editor Cut, Copy and Paste still route to the general clipboard; those commands were not exercised.

See the [runner instructions](../../Tests/AccessibilityUITests/README.md) for separate app/runner builds, all six provider form routes and evidence export. The audit app and corrected runner use local ad-hoc signing, not Developer ID or private signing keys.

## Native runner attempts

| Attempt/check | Observed result |
| --- | --- |
| Xcode UI runner build | Built successfully. This proves the runner compiled, not that an audit ran. |
| First launch, unsigned runner | Failed or hung before test execution. No audit findings were produced. |
| Corrected runner signature | `codesign --verify --deep --strict` passed after local ad-hoc signing. |
| Second launch, signed runner | Still stalled before test execution; the observed runner remained at `_dyld_start` with a 96K footprint. No test method or accessibility audit result was observed. |
| Permission evidence | Logs recorded a Developer Tools denial for `com.openai.codex`. Permission was requested from the user and remained unresolved at the end of this record. This is a likely blocker, not a confirmed sole cause of the runner stall; an authorized retry is needed to establish that. |
| Accessibility Inspector alternative | The Inspector target list omitted the menu-bar audit app (`LSUIElement`). No Inspector GUI audit ran. |

A successful build and valid signature cannot substitute for executing the tests. No clean audit, audit failure count or per-screen accessibility acceptance result can be inferred from these attempts.

The completed 16-case runner compiled successfully without launching UI. The normal optimized app build and signature verification also passed. The ordinary regression suite passed 133 checks; two opt-in checks (windowless rendering and live AI) were skipped. These results verify build/regression behavior, not native accessibility acceptance. The isolated app and both test runners were stopped after the attempt.

Audit-tooling checks confirmed that the launch preparation rejects the installed production app and accepts only the isolated audit bundle. The completion validator passed 14 synthetic result fixtures plus source/identity edge checks, and rejected the actual interrupted native result. Those fixtures test reporting safeguards; they are not native app test executions.

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
| A01 Discover and configure | Partial observations; **not PASS** | Editor/General labels and Settings open/close observed; VoiceOver discovery, all configuration controls and focus return not verified. |
| A02 Capture without a pointer | **NOT RUN** | No native capture or paste. |
| A03 Hear operation outcomes | **NOT RUN** | No verified live announcements or operation outcomes. |
| A04 Navigate and recover focus | Partial observations; **not PASS** | Settings open/close and a limited Tab attempt observed; full traversal, provider forms, VoiceOver modifiers and focus recovery not verified. |
| A05 Low vision | **NOT RUN** | No completed low-vision evaluation. Inspector toggle checks do not establish contrast, enlargement or Zoom acceptance. |
| A06 Alternative input and motion | **NOT RUN** | Voice Control, Switch Control and Reduce Motion acceptance not exercised. |

Native accessibility remains blocked under `clip-cqc.14`; text enlargement remains open under `clip-cqc.15`. Both continue to block candidate release acceptance (`clip-cqc.9`). This record does not change the project's partial-support status or claim accessibility conformance.
