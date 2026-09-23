# Smart Clipboard

<img src="docs/app-icon.png" alt="Smart Clipboard capture-frame icon" width="100">

**Capture something on your screen. Paste something useful.**

Turn a screenshot into editable text, notes, a table or structured data—or simply keep the image. Smart Clipboard lives in your Mac’s menu bar, uses your preferred output automatically, and stays out of the way while you work.

**[Download for Mac](https://github.com/colombod/smart-clipboard/releases)** · Apple Silicon (M1 or newer) · macOS 14+

Choose **[0.4 preview build 12](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.12)** for local AI, multiple providers, completion notifications, five interface languages and optional capture translation. It is an early release with [known limitations](docs/releases/v0.4.0-preview.md), especially local Description/SVG quality and accessibility. Official downloads are signed and notarized by Apple.

## Get started

### 1. Install

Download the **DMG**, open it, and drag **Smart Clipboard** into **Applications**. Eject the disk image and open the app.

Look for **Clip** in the menu bar at the top of your screen. There is no Dock icon and no window to keep open. Open **Clip → Settings & Status** when you need to configure it.

### 2. Choose how to process your captures

In **Settings → Connection**, select a connection and run **Test image processing**.

| Use this connection | If you want… |
| --- | --- |
| **Local / oMLX** | Image processing on your own Mac, with an installed vision model. [Set up local AI →](docs/USER-GUIDE.md#set-up-local-image-processing-with-omlx) |
| **OpenAI, Anthropic, Google Gemini or Perplexity** | To use an image-capable model through your own provider account and API key. [Connection setup →](docs/USER-GUIDE.md#choose-another-connection) |
| **ChatGPT via Codex** | To use an eligible ChatGPT/Codex account through the separately installed official Codex CLI. [Connection setup →](docs/USER-GUIDE.md#choose-another-connection) |

You can also choose **Pass through (image)** and skip AI setup entirely. API usage is billed by your provider; a ChatGPT subscription does not include API credits. Availability depends on your account, and not every cloud route has been tested live in this preview.

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
| Reconstruct markup or vector content | **HTML** or **SVG** |
| Describe what is visible | **Description** |

Captures keep the language in the image by default. To translate automatically, go to **Settings → General → Languages → Capture output** and choose **System language** or a specific language. **Default direction** is for other preferences, such as keeping table columns; the language choice takes priority over conflicting translation directions.

### 4. Capture and paste

1. Press **⌥⇧⌘3** and drag a rectangle, or **⌥⇧⌘4** to select a window.
2. The first time, allow Smart Clipboard to record your screen when macOS asks. Reopen it if requested.
3. Wait for **Clip ✓** or the **ready to paste** notification.
4. Press **⌘V** in your destination app.

That’s it—there is no Convert or Copy step after a capture, and no app window opens. **Space** switches between rectangle and window selection; **Escape** cancels. Customize shortcuts in **Settings → Shortcuts**; your saved shortcuts take precedence over the defaults above.

### 5. Know when it’s ready

In **Settings → General → Capture notifications**, enable macOS notifications and allow them when asked. Choose notifications for successful copies, failures, or both; sound is optional.

**Clip …** means the app is working. **Clip ✓** means the result has reached your clipboard. **Clip !** means something needs attention. Notifications contain a short status message, never your captured text. macOS notification settings and Focus determine how alerts appear.

## Keep useful captures

Open **Clip → History** to reuse an earlier capture. Pick another format or **Output language**, then choose **Convert with AI**. Each format and language has its own saved result, so translating into French keeps your earlier English or source-language version. **Saved formats** reopens those results without another AI request.

Choose how many captures to retain in **Settings → History**, delete individual entries, or clear them all. The default is 50. Setting the limit to zero clears saved history and stops saving new captures.

## Made to stay out of the way

Enable **Launch at login** in General settings to have it ready when you start your Mac. Closing Settings or History leaves the menu-bar app running. Its green capture-frame icon and windows follow macOS light and dark appearance.

Menus, settings, notifications and accessibility labels follow your Mac’s preferred supported language: English, Italian, Spanish, French or German. This does not change the language of captured content. Unsupported interface languages fall back to English. Restart the app after changing its language in macOS.

The app captures only when you ask. It does not continuously record your screen or monitor other apps’ clipboard contents. AI captures go to your selected provider; **Local / oMLX** on this Mac keeps image processing local. **Pass through** makes no AI request. Capture history stays on your Mac. [Privacy and storage details →](docs/USER-GUIDE.md#privacy-and-storage)

## Need a hand?

- **[Complete setup and usage guide](docs/USER-GUIDE.md)** — providers, models, notifications, history and updates.
- **[Capture troubleshooting](docs/USER-GUIDE.md#if-capture-does-not-work)** — permissions, shortcuts and local connections.
- **[Preview release notes](docs/releases/v0.4.0-preview.md)** — what changed and what still needs work.
- **[Accessibility status](docs/ACCESSIBILITY.md)** — current support and known gaps. Pointer-free capture and full VoiceOver use are not yet verified.
- **[Report a problem](https://github.com/colombod/smart-clipboard/issues/new)** — include your app version, macOS version and selected provider/model; leave out keys and private screenshots.

AI extraction can make mistakes. Review results before relying on them; HTML and SVG are copied as editable text, not rendered or executed by the app.

---

Want to contribute? Start with the [developer guide](docs/DEVELOPING.md), [provider test status](docs/PROVIDERS.md) or [signing and release guide](docs/SIGNING.md).
