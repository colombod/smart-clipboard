# Smart Clipboard

<img src="docs/app-icon.png" alt="Smart Clipboard capture-frame icon" width="100">

A native SwiftUI/AppKit menu bar app for macOS 14 or later. Capture a rectangle or window, then keep the image or convert it into editable content with OpenAI.

## Download and install

**[Download v0.3.1 signed preview](https://github.com/colombod/smart-clipboard/releases/tag/v0.3.1)** · Apple Silicon (M1 or newer) · macOS 14+

1. Download the `.dmg`, open it, and drag **Smart Clipboard** to **Applications**.
2. Eject the disk image and open the installed app. Look for the viewfinder button labelled **Clip** in the menu bar.
3. Open **Clip → Settings & Status → Shortcuts → Request screen access**, then approve Screen Recording in macOS. Choose your OpenAI connection in Settings.
4. In **Settings → General**, choose your **Preferred format** and optional **Default direction**. Captures always use this preference and copy automatically.
5. Enable **Launch at login** if you want it to start automatically.

The official v0.3.1 download is **Developer ID signed and Apple-notarized**. The app and DMG include validated notarization tickets, and both pass Gatekeeper assessment. Screen Recording and saved-key access still require your macOS approval. Updating from an older ad-hoc preview may require those approvals again once; history and preferences remain in their existing locations.

A ZIP is also available; extract it and move the app into Applications. `SHA256SUMS.txt` on the release page provides checksums. Intel Macs are not supported by this first binary release. See [the complete installation guide](docs/INSTALL.txt) for setup, updates and removal.

The app uses a green capture-frame icon, native system backgrounds/text and a forest-green accent. Windows follow the Mac’s light/dark appearance automatically.

## Build from source

The development branch adds Anthropic, Google Gemini, Perplexity and local oMLX connections alongside OpenAI and ChatGPT/Codex. See [connection setup and verification status](docs/PROVIDERS.md). These additions are not included in the public v0.3.1 download and still require live provider UAT.

```sh
./scripts/build-app.sh
open 'dist/Smart Clipboard.app'
```

Requires Apple Command Line Tools (`xcode-select --install`) and Swift 6 or later. SwiftPM fetches the pinned Yams dependency for YAML validation; its and libYAML's notices are included in the app. Open `Package.swift` in Xcode to work on the app. The build script creates an ad-hoc-signed app for local use. Set `SIGNING_IDENTITY` to sign with your own identity; a release that passes Gatekeeper without a manual exception also needs Developer ID signing and notarization.

Move the built app into `/Applications` before enabling **Settings → General → Launch at login**. The app starts silently in the menu bar without a Dock icon or any app window. Use Clip → Settings & Status for setup. Opening the running app from Applications brings its panel back. Closing a window leaves the app running; Quit is in the menu bar menu.

The development build also includes **Clip → About Smart Clipboard** and **Settings → About**. About shows the running app's version/build, Help & README, project/release/issue links, and bundled third-party notices. It opens only when requested and follows the Mac's appearance. The public v0.3.1 download does not include this new page yet.

## Capture and convert

- **⌥⇧⌘3**: capture a rectangle.
- **⌥⇧⌘4**: start in window selection mode.
- Press **Space** during capture to switch modes; **Escape** cancels.
- Configure both global shortcuts in Settings → Shortcuts. Conflicts are reported and the previous shortcut is restored.
- Set **Settings → General → Preferred format** once: Pass through (image), Description, Plain text, Markdown, HTML, SVG, JSON, YAML, or Auto detect. Add an optional **Default direction**, such as “Translate to English”.
- Capture a region/window. The app automatically converts it using your configured connection and copies the result. **Clip …** indicates work in progress; **Clip ✓** means it is ready to paste with **⌘V**. Pass through (image) copies the PNG directly without AI. Imported images use the same workflow.
- Open **Clipboard** or **History** explicitly to review a capture. In the editor, choose **Convert with AI**, or **Extract text on device** for offline Apple Vision OCR. Local OCR always returns plain text. **Copy after manual conversion** controls copying for these manual actions.
- Errors appear in the menu bar and do not replace the clipboard with a failed conversion. No app window opens automatically, including at startup or on error. Open **History** to review, edit, copy, or export a result, or convert the original into another format.

Capture requests Screen Recording permission if necessary and continues with the selected mode when permission is granted. If access is denied, the error stays in the menu bar; open Settings & Status explicitly for permission setup. Grant access in System Settings → Privacy & Security → Screen & System Audio Recording, then restart the app if needed. Capture uses the built-in macOS interactive screenshot selector, including multi-display selection. `screencapture` receives only the selected region/window; there is no continuous screen monitoring.

## Auto detect and capture history

Choose **Auto detect** in the output sidebar, or set it as **Settings → General → Preferred format**. On conversion, AI chooses an editable format from the original source: plain text for prose, Markdown for documents/tables, JSON or YAML for records/configuration, HTML for web layouts, SVG for simple diagrams, or a description for photos. The result shows the actual chosen format. You can override it any time.

Open **History** from the sidebar or menu bar. Entries show a thumbnail, capture date, and saved formats. Select **Open**, pick a different output format, and convert the original image again. **Saved formats** retrieves a previous result without a new AI request. Each capture keeps the latest result per format; regenerating one format leaves the others intact. Editor changes are saved when switching clips/results, copying/exporting, starting another conversion, closing the working clip, or quitting normally.

In **Settings → History**, set the maximum clip count (0–500, default 50), then click **Apply limit**. Oldest captures and their original image files are removed first. Zero clears saved clips and disables history for future captures. Use the trash button on an entry to delete it, or **Clear history** to remove all captures/results and close the active clip. Deletions do not erase exported files or the system clipboard.

Storage: `~/Library/Application Support/Smart Clipboard/History/`. Original PNGs are stored alongside a metadata/result index. Files are restricted to your macOS user (folder 0700, files 0600), but are not separately encrypted by the app. History is only for captures and images imported into Smart Clipboard; it does not monitor the system clipboard. The limit counts captures, so disk usage depends on image sizes; Settings also shows the current disk usage.

## Connect to OpenAI

**API key:** In Settings → Connection, choose OpenAI API key, paste a key, and save it. Keys are stored in macOS Keychain. Settings never reads a saved key automatically. After an ad-hoc update, use **Authorize saved key** if Keychain access needs approval; background capture reports access errors in the menu bar without opening a dialog. The editable default model is `gpt-5.6-luna`; choose an image-capable model supporting structured outputs available to your API account. Requests use the Responses API with a JSON schema and `store: false`. API usage is billed separately through OpenAI Platform.

**ChatGPT subscription:** Install a recent official Codex CLI, select ChatGPT via Codex, then click Sign in with ChatGPT and complete the browser flow. Alternatively, an existing `codex login` session works. Check connection verifies that Codex reports a ChatGPT login. The CLI must support `--ignore-user-config` (update it if necessary). An optional executable path handles nonstandard installations; an empty model uses the CLI's built-in default.

The subscription integration invokes the official CLI's non-interactive image support; it is not a standalone ChatGPT OAuth client or an API billing workaround. Availability and limits depend on the account’s Codex entitlement and workspace policies. Credentials remain managed by Codex. The app checks login type, forces ChatGPT auth for conversions, strips inherited API keys from the child environment, and does not read authentication files.

Codex conversions use a private temporary working directory, ephemeral sessions, read-only sandbox, no user config, disabled shell/patch/collaboration features and disabled web search. No plugins or MCP servers from the user's config are loaded. A conversion is image analysis only; temporary captures/results are removed when the operation ends. Cancellation terminates the child process. Do not use an untrusted replacement for the configured executable.

Official references: [Authentication](https://learn.chatgpt.com/docs/auth), [Non-interactive Codex](https://learn.chatgpt.com/docs/non-interactive-mode), [Image input](https://developers.openai.com/api/docs/guides/images-vision).

## Privacy and output behavior

After capture, each selected screenshot or imported image is sent to your configured AI connection and the result replaces the system clipboard. Selecting **Pass through (image)** copies the PNG locally without AI. Image copy/save and local OCR work without a connection. By default, the app saves the 50 most recent captures/imports and their generated results locally. Change this in Settings → History; setting the limit to zero removes saved history and disables future saving. Exporting writes a file; successful automatic processing and the Copy actions update the system clipboard. Saved history survives quitting the app. Close a working clip with the × button without deleting its history; delete an entry in History or use Clear history to remove saved originals and results. The system clipboard and exported files survive app exit. OpenAI data handling follows the selected API account or ChatGPT workspace policy; `store: false` does not imply zero retention.

AI extraction and vector reconstruction can be imperfect. Screenshot instructions are treated as untrusted data. JSON is validated before acceptance; YAML/HTML/SVG are returned as editable source, not rendered or executed, and require review for correctness. Copying output uses plain-text clipboard content, including markup formats. Large or complex captures may exceed model limits; try a smaller region.

## Validate

The intended background workflow and observable release gates are defined in [User experience and UAT](docs/UAT.md). Automated tests and imported-image checks do not replace a real global-shortcut → selection → paste run. Current acceptance results and unresolved gates are tracked in Beads.

For local-model development, see [the oMLX synthetic-image test instructions and observed limitations](docs/testing/OMLX.md). Passing automated checks alone does not establish Description/SVG quality or native capture acceptance.

```sh
./scripts/test.sh
```

Tests cover preferred-format capture/import automation, clipboard success/failure/cancellation, permission routing, shortcuts, all provider request/response contracts, JSON/YAML validation, settings migration and profile isolation, history provenance and retention, child-process cancellation/timeouts, and on-device OCR against a generated fixture. Run the OCR test outside restrictive automation sandboxes so Vision can access macOS image buffers. Set `SMART_CLIPBOARD_RENDER_DIR` to a temporary directory to opt into windowless light/dark Settings renders. Live AI calls require a configured account. macOS screen permissions, interactive selection and login-item approval require testing in a logged-in GUI session. Project task tracking lives in Beads (`bd`).

## Package a release

For a public release, configure a Developer ID Application identity and a local notarization profile using the [signing guide](docs/SIGNING.md), then run:

```sh
SIGNING_IDENTITY="YOUR_CERTIFICATE_SHA1" \
NOTARY_PROFILE="smart-clipboard-notary" \
NOTARY_TIMEOUT=60s \
./scripts/notarize-release.sh
```

If Apple is still processing the submission, leave `dist/` unchanged and append `--resume` to the same command. The pipeline signs and notarizes the app and DMG, staples both tickets, verifies Gatekeeper acceptance, and computes final checksums. It preserves the exact approved app throughout packaging. Orchestration checks run with `bash Tests/ReleaseScripts/test-release.sh`.

For a local development package without notarization:

```sh
./scripts/package-release.sh
```

Both paths build for the current Mac’s architecture and write a DMG, ZIP, and SHA-256 checksums into `dist/`. The DMG includes the app, an Applications shortcut, and installation instructions. The capture-frame application icon is generated from vector drawing code in `scripts/generate-icon.swift`.

Earlier builds were exercised with real region capture, live AI conversion and pasting into TextEdit on the development Mac. That evidence does not verify the multiple-provider candidate: its live provider, native-capture and signed-update gates remain pending in [UAT.md](docs/UAT.md). No credentials, captures, local issue database, or compiled build cache are published in source.

### Capture readiness and shortcut conflicts

**Clip → Settings & Status → Shortcuts** shows the app's running status, Screen Recording permission, and a separate registration result for each capture shortcut. The capture action requests permission directly; denial leaves an error in the menu bar without opening an app window. Open Settings explicitly, use **Request screen access**, approve the macOS prompt yourself, then **Check again**; reopen the app if macOS requests it.

Shortcut recording rejects enabled macOS shortcuts, duplicate capture bindings and conflicting registered hotkeys. **Find available shortcuts** tries alternatives for unavailable bindings without changing working ones. A rejected replacement keeps the previous shortcut. Keyboard utilities that intercept events may not expose their bindings to macOS; the last-received shortcut timestamp helps diagnose those cases. Screen permission and shortcut registration are independent requirements.

The app keeps one instance running even when a development or downloaded copy is opened. The menu bar button has both a native template icon and a text label, and reappears when the running app is reopened. macOS can still hide menu items when the bar is crowded.

Ad-hoc preview updates can invalidate a previous Screen Recording grant even if System Settings still shows the switch enabled. If restarting and toggling the switch does not help, quit Smart Clipboard and run `tccutil reset ScreenCapture com.smartclipboard.app` in Terminal. Then add `/Applications/Smart Clipboard.app` again in System Settings → Privacy & Security → Screen & System Audio Recording, approve it, and reopen the app. This resets only Smart Clipboard’s Screen Recording grant. Stable certificate signing is required before promising permission continuity across releases.
