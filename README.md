# Smart Clipboard

<img src="docs/app-icon.png" alt="Smart Clipboard capture-frame icon" width="100">

**Capture something on your screen. Paste something useful.**

Turn a screenshot into editable text, notes, a table, structured data or vector artwork—or keep the image. Smart Clipboard lives in your Mac’s menu bar, uses your preferred output automatically, and stays out of the way while you work.

**[Download for Mac](https://github.com/colombod/smart-clipboard/releases/download/v0.4.0-preview.14/Smart-Clipboard-0.4.0-macOS-arm64.dmg)** · Apple Silicon (M1 or newer) · macOS 14+

The current public preview is **[0.4 preview build 14](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.14)**, with local SVG tracing, five interface languages, optional capture translation, multiple AI providers and completion notifications. It is an early release with [known limitations](docs/releases/v0.4.0-preview.md), especially AI Description/SVG quality and accessibility. Official downloads are signed and notarized by Apple.

## Get started

### 1. Install

Download the **DMG**, open it, and drag **Smart Clipboard** into **Applications**. Eject the disk image and open the app.

Look for **Clip** in the menu bar at the top of your screen. There is no Dock icon and no window to keep open. Open **Clip → Settings & Status** when you need to configure it.

### 2. Choose how to process your captures

For photos, logos and drawings, **SVG → Trace on device** works without AI setup. [Set up picture tracing →](#turn-a-picture-into-svg) **Pass through (image)** also needs no AI connection.

For AI extraction or reconstruction, select a connection in **Settings → Connection** and run **Test image processing**.

| Use this connection | If you want… |
| --- | --- |
| **Local / oMLX** | Image processing on your own Mac, with an installed vision model. [Set up local AI →](docs/USER-GUIDE.md#set-up-local-image-processing-with-omlx) |
| **OpenAI, Anthropic, Google Gemini or Perplexity** | To use an image-capable model through your own provider account and API key. [Connection setup →](docs/USER-GUIDE.md#choose-another-connection) |
| **ChatGPT via Codex** | To use an eligible ChatGPT/Codex account through the separately installed official Codex CLI. [Connection setup →](docs/USER-GUIDE.md#choose-another-connection) |

API usage is billed by your provider; a ChatGPT subscription does not include API credits. Availability depends on your account, and not every cloud route has been tested live in this preview.

**Starting with oMLX?** Our smaller tested option is **Qwen3-VL-8B-Instruct-4bit** for text, tables and structured extraction. The 32B model uses substantially more memory and did not fix the Description/SVG problems in our tests. Use the [model guide](docs/USER-GUIDE.md#choose-a-local-model) for exact downloads, memory guidance and the compatible server version.

### 3. Set your preferred result

In **Settings → General → Preferred format**, choose once:

| What you need | Choose |
| --- | --- |
| Let AI choose a useful format | **Auto detect** |
| Keep the screenshot as an image | **Pass through (image)** |
| Copy words into another app | **Plain text** |
| Keep headings, lists or tables | **Markdown** |
| Extract a record or configuration | **JSON** or **YAML** |
| Reconstruct web markup | **HTML** |
| Trace a picture or reconstruct vector artwork | **SVG** — [choose a method below](#turn-a-picture-into-svg) |
| Describe what is visible | **Description** |

Use **Default direction** for preferences such as keeping table columns.

Captures keep the language in the image by default. To translate automatically, go to **Settings → General → Languages → Capture output** and choose **System language** or a specific language. This choice takes priority over conflicting translation directions.

### 4. Capture and paste

1. Press **⌥⇧⌘3** and drag a rectangle, or **⌥⇧⌘4** to select a window.
2. The first time, allow Smart Clipboard to record your screen when macOS asks. Reopen it if requested.
3. Wait for **Clip ✓** or the **ready to paste** notification.
4. Press **⌘V** in your destination app.

That’s it—there is no Convert or Copy step after a capture, and no app window opens. **Space** switches between rectangle and window selection; **Escape** cancels. Customize shortcuts in **Settings → Shortcuts**; your saved shortcuts take precedence over the defaults above.

### 5. Know when it’s ready

In **Settings → General → Capture notifications**, enable macOS notifications and allow them when asked. Choose notifications for successful copies, failures, or both; sound is optional.

**Clip …** means the app is working. **Clip ✓** means the result has reached your clipboard. **Clip !** means something needs attention. Notifications contain a short status message, never your captured text. macOS notification settings and Focus determine how alerts appear.

## Turn a picture into SVG

Use **Trace on device** for a scalable version of a photo, pet, logo or drawing. Choose **Reconstruct with AI** to have a model interpret and rebuild a simple diagram or illustration. AI can change or invent details; local tracing follows visible shapes and colours. AI reconstruction remains the default after upgrading, so select tracing explicitly when you want it.

To trace pictures with your usual capture shortcut:

1. Open **Settings → General**, set **Preferred format** to **SVG**, then set **SVG method** to **Trace on device**.
2. Choose **Photo** for photos, **Logo** for flat artwork, or **Line drawing** for clear outlines. Start with **Balanced**; **Detailed** preserves more shapes and colours and creates larger files.
3. Close Settings, capture a rectangle or window, wait for **Clip ✓**, then paste.

The clipboard contains **SVG source text**. For a vector editor, open the result in **History**, choose **Save…**, and open or import the `.svg` file. You can also trace an earlier screenshot from History and keep multiple preset/detail versions.

Tracing works offline with the helper included in the app. It needs no AI account, downloaded model, server or extra setup. Words become outlines, the background stays, and translation and directions do not apply. It does not remove backgrounds automatically or recover chart data. A failed trace leaves your clipboard unchanged and does not switch to AI.

For AI reconstruction, configure and test an image-capable connection, choose **SVG → Reconstruct with AI**, then capture as usual. [Step-by-step SVG guide →](docs/USER-GUIDE.md#trace-a-picture-to-svg)

## Keep useful captures

Open **Clip → History** to reuse an earlier capture. Pick another format, then choose **Convert with AI**. **Saved formats** reopens existing results without another AI request.

Choose an **Output language** to translate a saved capture. Each format and language is saved separately, so translating into French keeps your earlier English or source-language version.

Choose how many captures to retain in **Settings → History**, delete individual entries, or clear them all. The default is 50. Setting the limit to zero clears saved history and stops saving new captures.

## Made to stay out of the way

Enable **Launch at login** in General settings to have it ready when you start your Mac. Closing Settings or History leaves the menu-bar app running. Its green capture-frame icon and windows follow macOS light and dark appearance.

Menus, settings, notifications and accessibility labels use English, Italian, Spanish, French or German, following your Mac’s preferred supported language. This does not change the language of captured content. Unsupported interface languages fall back to English. Restart the app after changing its language in macOS.

The app captures only when you ask. It does not continuously record your screen or monitor other apps’ clipboard contents. AI captures go to your selected provider; **Local / oMLX** on this Mac keeps image processing local. **Pass through** and **Trace on device** make no AI request. Capture history stays on your Mac. [Privacy and storage details →](docs/USER-GUIDE.md#privacy-and-storage)

## Need a hand?

- **[Complete setup and usage guide](docs/USER-GUIDE.md)** — providers, models, notifications, history and updates.
- **[Capture troubleshooting](docs/USER-GUIDE.md#if-capture-does-not-work)** — permissions, shortcuts and local connections.
- **[Preview release notes](docs/releases/v0.4.0-preview.md)** — what changed and what still needs work.
- **[Accessibility status](docs/ACCESSIBILITY.md)** — current support and known gaps. Pointer-free capture and full VoiceOver use are not yet verified.
- **[Report a problem](https://github.com/colombod/smart-clipboard/issues/new)** — include your app version, macOS version and selected provider/model; leave out keys and private screenshots.

AI extraction can make mistakes. Review results before relying on them; HTML and SVG are copied as editable text, not rendered or executed by the app.

---

Want to contribute? Start with the [developer guide](docs/DEVELOPING.md), [provider test status](docs/PROVIDERS.md) or [signing and release guide](docs/SIGNING.md).
