# Smart Clipboard

<img src="docs/app-icon.png" alt="Smart Clipboard capture-frame icon" width="100">

**Capture something on your screen. Paste something useful.**

A quiet Mac menu-bar app that turns a screenshot into text, a table, structured data or SVG. Set your preferences once, then capture and paste without opening the app.

**[Download for Mac](https://github.com/colombod/smart-clipboard/releases/download/v0.4.0-preview.15/Smart-Clipboard-0.4.0-macOS-arm64.dmg)** · Apple Silicon · macOS 14+ · Signed and notarized

Current version: **[0.4 preview build 15](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.15)**. [Known preview limitations](docs/releases/v0.4.0-preview.md).

## Get started

1. **Install:** open the DMG and drag Smart Clipboard into **Applications**. Open it and look for **Clip** in the menu bar.
2. **Set up once:** open **Clip → Settings & Status**. Choose your output in **General**, and an AI connection if needed.
3. **Capture and paste:** close Settings, press **⌃⌘R**, select an area, wait for **Clip ✓**, then press **⌘V** in your destination app.

Use **⌃⌘W** for a window. **Space** switches selection modes; **Escape** cancels. Your saved custom shortcuts take precedence. Approve Screen Recording when macOS asks.

## Choose what you want to paste

[![General settings showing Auto detect as the preferred format and Keep source language for capture output.](docs/images/capture-settings.png)](docs/images/capture-settings.png)

*Choose the output once. Settings can stay closed while you work. Select any screenshot to enlarge it.*

- **Auto detect:** let AI choose a useful format.
- **Plain text, Markdown, HTML, JSON or YAML:** choose a specific editable result.
- **Pass through:** keep the image, without AI.
- **SVG:** trace shapes locally or reconstruct with AI.

For AI processing, use your own cloud account or **Local / oMLX**. [Connection setup →](docs/USER-GUIDE.md#set-up-local-image-processing-with-omlx)

## Turn a picture into SVG

[![SVG capture settings with Trace on device, Photo preset and Balanced detail selected.](docs/images/svg-tracing.png)](docs/images/svg-tracing.png)

*General → SVG → Trace on device. No account, model or server required.*

Choose **Photo**, **Logo** or **Line drawing**, then capture as usual. **Balanced** keeps files smaller; **Detailed** preserves more shapes and colours. Paste the SVG source, or use **History → Open → Save…** to import it into a vector editor.

Tracing keeps the background and turns words into outlines. For model-based reconstruction, choose **Reconstruct with AI** instead. [Tracing guide →](docs/USER-GUIDE.md#trace-a-picture-to-svg)

## Reuse a capture

[![History showing sample captures with separately saved text, Markdown and French versions.](docs/images/history.png)](docs/images/history.png)

*Open History only when you need it. Reuse an original without taking another screenshot.*

Choose another format or language, then convert. **Saved formats** reopens earlier results; **Copy** puts one on the clipboard. Set your history limit or clear saved clips in **Settings → History**.

## Know when it is ready

**Clip …** means working. **Clip ✓** means ready to paste. **Clip !** means open the menu to read the problem.

Enable optional success/failure notifications and sound in **General**. Focus or screen sharing can suppress alerts; the menu status remains available. [Notification help →](docs/USER-GUIDE.md#completion-and-failure-notifications)

## Need a hand?

[Illustrated user guide](docs/USER-GUIDE.md) · [Local model setup](docs/USER-GUIDE.md#choose-a-local-model) · [Translation](docs/USER-GUIDE.md#languages-and-translation) · [Troubleshooting](docs/USER-GUIDE.md#if-capture-does-not-work)

The app follows macOS light/dark appearance and supports English, Italian, Spanish, French and German. Captures keep their source language unless you enable translation. Local tracing works offline; AI captures go to your selected connection. [Privacy details](docs/USER-GUIDE.md#privacy-and-storage).

*Screenshots show the current app’s views with sample data. This is a preview: AI results need review, cloud coverage and full [accessibility acceptance](docs/ACCESSIBILITY.md) remain incomplete.*

[Report a problem](https://github.com/colombod/smart-clipboard/issues/new) · [Developer guide](docs/DEVELOPING.md)
