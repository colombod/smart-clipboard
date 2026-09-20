# Smart Clipboard

A native SwiftUI/AppKit menu bar app for macOS 14 or later. Capture a rectangle or window, then keep the image or convert it into editable content with OpenAI.

## Download and install

**[Download v0.1.0 preview](https://github.com/colombod/smart-clipboard/releases/tag/v0.1.0)** · Apple Silicon (M1 or newer) · macOS 14+

1. Download the `.dmg`, open it, and drag **Smart Clipboard** to **Applications**.
2. Eject the disk image and open the installed app. Look for the capture-frame icon in the menu bar.
3. Allow Screen Recording when you first capture. Choose your OpenAI connection in Settings.
4. Enable **Settings → General → Launch at login** if you want it to start automatically.

This initial preview is **ad-hoc signed and not Apple-notarized**. If macOS blocks opening it, review [Apple’s instructions](https://support.apple.com/en-us/102445) and use **System Settings → Privacy & Security → Open Anyway** only if you trust this download. Managed Macs may disallow that exception. A Developer ID certificate and notarization are needed for a future release without this extra step.

A ZIP is also available; extract it and move the app into Applications. `SHA256SUMS.txt` on the release page provides checksums. Intel Macs are not supported by this first binary release. See [the complete installation guide](docs/INSTALL.txt) for setup, updates and removal.

The app uses a green capture-frame icon, native system backgrounds/text and a forest-green accent. Windows follow the Mac’s light/dark appearance automatically.

## Build from source

```sh
./scripts/build-app.sh
open 'dist/Smart Clipboard.app'
```

Requires Apple Command Line Tools (`xcode-select --install`), Swift 6 or later, and no third-party Swift dependencies. Open `Package.swift` in Xcode to work on the app. The build script creates an ad-hoc-signed app for local use. Set `SIGNING_IDENTITY` to sign with your own identity; a release that passes Gatekeeper without a manual exception also needs Developer ID signing and notarization.

Move the built app into `/Applications` before enabling **Settings → General → Launch at login**. The app opens its capture panel on first launch, then runs in the menu bar without a Dock icon. Closing a window leaves the app running; Quit is in the menu bar menu.

## Capture and convert

- **⌥⇧⌘3**: capture a rectangle.
- **⌥⇧⌘4**: start in window selection mode.
- Press **Space** during capture to switch modes; **Escape** cancels.
- Configure both global shortcuts in Settings → Shortcuts. Conflicts are reported and the previous shortcut is restored.
- Choose Image, Description, Plain text, Markdown, HTML, SVG, JSON, YAML, or Smart format.
- Add an optional instruction, such as “Translate to English” or “Use one record per table row.”
- Choose **Convert with AI**, or **Extract text on device** for offline Apple Vision OCR. Local OCR ignores AI directions and always returns plain text.
- Edit the output, copy it, or save it using the format’s file extension. The original PNG remains available independently.

macOS requests Screen Recording permission at first capture. Grant it in System Settings → Privacy & Security → Screen & System Audio Recording, then restart the app if needed. Capture uses the built-in macOS interactive screenshot selector, including multi-display selection. `screencapture` receives only the selected region/window; there is no continuous screen monitoring.

## Connect to OpenAI

**API key:** In Settings → Connection, choose OpenAI API key, paste a key, and save it. Keys are stored in macOS Keychain. The editable default model is `gpt-5.6-luna`; choose an image-capable model supporting structured outputs available to your API account. Requests use the Responses API with a JSON schema and `store: false`. API usage is billed separately through OpenAI Platform.

**ChatGPT subscription:** Install a recent official Codex CLI, select ChatGPT via Codex, then click Sign in with ChatGPT and complete the browser flow. Alternatively, an existing `codex login` session works. Check connection verifies that Codex reports a ChatGPT login. The CLI must support `--ignore-user-config` (update it if necessary). An optional executable path handles nonstandard installations; an empty model uses the CLI's built-in default.

The subscription integration invokes the official CLI's non-interactive image support; it is not a standalone ChatGPT OAuth client or an API billing workaround. Availability and limits depend on the account’s Codex entitlement and workspace policies. Credentials remain managed by Codex. The app checks login type, forces ChatGPT auth for conversions, strips inherited API keys from the child environment, and does not read authentication files.

Codex conversions use a private temporary working directory, ephemeral sessions, read-only sandbox, no user config, disabled shell/patch/collaboration features and disabled web search. No plugins or MCP servers from the user's config are loaded. A conversion is image analysis only; temporary captures/results are removed when the operation ends. Cancellation terminates the child process. Do not use an untrusted replacement for the configured executable.

Official references: [Authentication](https://learn.chatgpt.com/docs/auth), [Non-interactive Codex](https://learn.chatgpt.com/docs/non-interactive-mode), [Image input](https://developers.openai.com/api/docs/guides/images-vision).

## Privacy and output behavior

Captures remain local until **Convert with AI** is chosen. Image copy/save and local OCR work without a connection. The app does not persist capture history. Exporting explicitly writes a file; copying explicitly updates the system clipboard. Results and captures remain in memory until discarded/replaced or the app quits. The system clipboard and exported files survive app exit. OpenAI data handling follows the selected API account or ChatGPT workspace policy; `store: false` does not imply zero retention.

AI extraction and vector reconstruction can be imperfect. Screenshot instructions are treated as untrusted data. JSON is validated before acceptance; YAML/HTML/SVG are returned as editable source, not rendered or executed, and require review for correctness. Copying output uses plain-text clipboard content, including markup formats. Large or complex captures may exceed model limits; try a smaller region.

## Validate

```sh
./scripts/test.sh
```

The 16 tests cover conversion envelopes, output selection, JSON validity, refusals/truncation, Responses API payloads, child-process cancellation/timeouts, and on-device OCR against a generated fixture. Run the OCR test outside restrictive automation sandboxes so Vision can access macOS image buffers. Live AI calls require a configured account. macOS screen permissions, interactive selection and login-item approval require testing in a logged-in GUI session. Project task tracking lives in Beads (`bd`).

## Package a release

```sh
./scripts/package-release.sh
```

This builds for the current Mac’s architecture and writes a DMG, ZIP, and SHA-256 checksums into `dist/`. The DMG includes the app, an Applications shortcut, and installation instructions. The capture-frame application icon is generated from vector drawing code in `scripts/generate-icon.swift`.

The initial preview has passed its 16 automated tests and release-build/signature checks. Interactive capture across multiple displays, login-item approval and live API/ChatGPT conversions still need hands-on acceptance testing with configured accounts. No credentials, captures, local issue database, or compiled build cache are published in source.
