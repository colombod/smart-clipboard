# Native accessibility audits

This Xcode UI Testing Bundle targets only `com.smartclipboard.accessibility-audit`, built separately with the compile-time `ACCESSIBILITY_AUDIT` fixture. It must never target the installed production app. Normal builds cannot enable the fixture through launch arguments.

The fixture uses actual production views and AppModel with in-memory app preferences, temporary history, a private AppModel pasteboard, synthetic images, mock conversion and a hotkey backend that registers no global shortcuts. Service and permission actions are guarded in the audit build. Tests do not invoke capture, provider requests, Keychain, login or permission-control actions. Announcements go to an injected collector by default; only the explicit `--audit-voiceover-announcements` argument enables live VoiceOver announcement requests.

**Clipboard boundary:** the AppModel's copy operations use the private fixture pasteboard, but native editor Cut, Copy and Paste commands still use the actual general clipboard through AppKit's responder chain. Automated audits deliberately avoid those commands and clipboard actions. The harness is not a system-wide clipboard sandbox.

Build the separate app and runner without launching UI:

```sh
scripts/build-accessibility-audit.sh
scripts/test-accessibility.sh --build-only
```

The first script compiles with `-DACCESSIBILITY_AUDIT` in a separate build directory and creates `dist/Smart Clipboard Audit.app`; it does not replace the installed app. The app and Xcode runner use local **ad-hoc signing** (`CODE_SIGN_IDENTITY=-` for the runner). This is not Developer ID signing and does not need a developer team or private signing keys. Signing does not grant macOS privacy or Developer Tools permissions.

After arranging an authorized interactive native UI test session, execute:

```sh
scripts/test-accessibility.sh --results /tmp/smart-clipboard-accessibility
```

`--app` (or `SMART_CLIPBOARD_AUDIT_APP`) selects the separate audit bundle. `--results` (or `SMART_CLIPBOARD_AUDIT_RESULTS`) selects the evidence directory; the default creates a fresh timestamped directory under the system temporary directory. Keep raw results in a temporary or ignored directory: Xcode's automatic failure captures may include desktop content. An existing `.xcresult` is never overwritten. `--only-testing AccessibilityAuditTests/testSettingsAbout` restricts a diagnostic run; it does not establish full-suite acceptance.

The startup test checks that no app window opens automatically, opens Settings with Command-comma, selects its real native tabs, and closes Settings with Command-W. Independent tests launch General, Connection, Shortcuts, History and About Settings screens and empty/populated editor/history windows using `--audit-screen SCREEN` and optional `--audit-populated`. No screen argument preserves quiet startup.

Connection tests select and verify every provider form through `--audit-provider VALUE`. These are form audits using synthetic state, not provider connectivity tests:

| Form | Argument value |
| --- | --- |
| OpenAI | `openai` |
| ChatGPT via Codex | `codex` |
| Anthropic | `anthropic` |
| Google Gemini | `google` |
| Perplexity | `perplexity` |
| Local / oMLX | `omlx` |

The default Connection fixture uses oMLX. Supported screen arguments are `settings-general`, `settings-connection`, `settings-shortcuts`, `settings-history`, `settings-about`, `editor` and `history`.

Each visible screen uses `XCUIApplication.performAccessibilityAudit(for: .all)`. The handler returns `false` for every finding, so Xcode records failures without an ignore list. Reports retain per-screen findings, accessibility trees and screenshots of the audit window as XCTest attachments. The script exports those attachments plus summary/test JSON, records the audited executable's checksum, and preserves failed exit status. Before reporting success, it verifies that every selected test actually executed and passed, with no skips or missing cases. Unknown result formats fail closed; a successful build or empty test run cannot count as an audit pass.

Use an interactive macOS session with Xcode's UI testing prerequisites already satisfied. The script selects local ad-hoc signing for its runner build; it does not install certificates or change privacy permissions, automation permissions or system security settings. If Xcode cannot run the audit, the run remains incomplete; do not bypass that failure or report a clean audit. The [22 September 2026 execution record](../../docs/testing/ACCESSIBILITY-NATIVE.md) is **BLOCKED**: the runner built, but no accessibility audit executed.

These are native audits of synthetic UI states, not production capture/focus/paste acceptance. The macOS SDK supports contrast, element detection, hit regions, descriptions, actions and parent-child audits; its API does not expose the iOS Dynamic Type category. Automated audits also do not replace manual VoiceOver and keyboard testing. See [Apple's accessibility audit documentation](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app).
