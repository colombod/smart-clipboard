# Using Smart Clipboard

Smart Clipboard stays in the menu bar. Set your connection and preferred output once, then capture and paste into the app you are already using.

## Install and start

Download the signed DMG from [GitHub Releases](https://github.com/colombod/smart-clipboard/releases), open it and drag **Smart Clipboard** into **Applications**. Eject the DMG and open the installed app. Look for **Clip** in the menu bar; no app window should open.

Open **Clip → Settings & Status** when you want to change a setting. Closing Settings leaves capture shortcuts working. **Clip → Quit Smart Clipboard** stops the app. Enable **Launch at login** in General if you want it to start with your Mac.

Official downloads are for Apple Silicon and macOS 14 or later. A local oMLX server has its own hardware and macOS requirements.

## Set up local image processing with oMLX

1. Start your oMLX server and download a model that accepts images. Our initial test model is **mlx-community/Qwen3-VL-8B-Instruct-4bit**. A text-only model cannot read screenshots.
2. Open Smart Clipboard **Settings → Connection** and select **Local / oMLX**.
3. Enter the server address shown by oMLX, ending in `/v1`. For example, a server on this Mac using port 8999 is `http://127.0.0.1:8999/v1`. The port must match your server; 8999 is not a universal default.
4. Click **Refresh models**, then choose the exact listed vision model. For our downloaded checkpoint the model ID is `Qwen3-VL-8B-Instruct-4bit`.
5. If your server requires a key, enter it and click **Save key**. An unauthenticated server on this Mac needs no key. A server on another computer requires a key; use HTTPS outside a private local network.
6. Click **Test image processing**. This sends a generated sample image, not your screen or saved captures. A successful model listing alone does not prove image support.
7. In **General**, choose **Auto detect** or an explicit preferred output, then close Settings.

**Server compatibility:** oMLX 0.6.4 has a known bug affecting structured output from this vision model. Smart Clipboard rejects incomplete responses instead of copying them. The official 0.7.0.dev2 preview includes the upstream fix; consult the Smart Clipboard release notes and [local test evidence](testing/OMLX.md) for the exact tested configuration. Merely installing a larger model does not fix this server bug.

oMLX must remain running while you use AI extraction. Smart Clipboard connects to it; it does not start the server, download models or switch to a cloud service if local processing fails. With the server on `127.0.0.1`, captures are sent to this Mac. A remote server receives the selected capture.

## Capture, wait, paste

The default shortcuts are **⌥⇧⌘3** for a rectangle and **⌥⇧⌘4** for a window. Your saved custom shortcuts take precedence; view or change them in **Settings → Shortcuts**.

1. Keep the destination app open.
2. Press your capture shortcut. Drag a rectangle, or click the window you want. **Space** switches selection modes; **Escape** cancels.
3. Wait for **Clip ✓** in the menu bar.
4. Paste with **⌘V** in your destination app.

**Clip …** means capture or conversion is in progress. **Clip !** means something needs attention: open the menu to read the error. Failed or cancelled conversion preserves the previous clipboard contents. Settings and the editor do not open automatically.

The first capture may require Screen Recording approval from macOS. In **Settings → Shortcuts**, choose **Request screen access**, approve Smart Clipboard in System Settings, and reopen the app if macOS requests it. A software update can occasionally require permission approval again.

## Choose the output once

In **Settings → General → Preferred format**, choose:

| Format | What is copied |
| --- | --- |
| Auto detect | An editable format chosen from the captured content, using your selected AI connection. |
| Pass through (image) | The selected image, with no extraction or AI request. |
| Plain text | Extracted text without added document markup. |
| Markdown | Editable document or table markup. |
| JSON / YAML | Structured data reconstructed from the source. |
| HTML | Editable HTML source. |
| SVG | Editable vector source; reconstruction may be approximate. |
| Description | A written description of the image. |

All AI outputs, including HTML and SVG, are copied as text. The app does not render or execute generated markup. **Default direction** adds an instruction to subsequent captures, for example “Translate to English.” AI output can contain mistakes; our small local model has known Description and SVG quality limitations documented in the release notes.

## Reuse a previous capture

Choose **Clip → History**, open a capture, select another format and click **Convert with AI**. The original image is reused. **Saved formats** retrieves an already generated result without another AI request. **Extract text on device** uses Apple's local text recognition and returns plain text without an AI connection.

In **Settings → History**, choose the maximum number of saved clips and apply the limit. The default is 50; the maximum is 500. Oldest clips are removed first. Zero clears and disables history. You can delete one clip or clear all history. Deletion does not remove exported files or change what is already on the system clipboard.

History stores your selected/imported images and results locally. It does not watch other apps' clipboard activity.

## Updates

Updater-enabled releases provide **Check for Updates…** in the Clip menu and About page. Enable daily background checks in About if desired. An available update is indicated in the menu without opening a window. Select it to review and install; capture or conversion must finish first.

Stable releases are the default. In About, set **Releases → Stable and preview releases** only if you want development previews. A preview can include known limitations listed in its release notes. Updates keep your preferences and saved history. They do not change your selected AI connection.

Older releases without an updater need one manual replacement with an updater-enabled release. Quit the old app before dragging the new one into Applications. Keep using official signed downloads.

## If capture does not work

| Symptom | Check |
| --- | --- |
| No Clip menu | Open the installed app. A crowded menu bar may hide items. |
| Shortcut does nothing | Open Settings → Shortcuts and check permission and each shortcut's registration status. Record another shortcut or use Find available shortcuts if there is a conflict. |
| Local server unavailable | Start oMLX and confirm the address and port in Connection. |
| Model unavailable | Refresh models and select the exact installed vision model. |
| Repeated text or unfinished conversion | Check the oMLX version; 0.6.4 has the structured-output bug described above. |
| Capture copied an image | Preferred format is Pass through; select Auto detect or another format for extraction. |
| Pasting shows the previous item | Wait for Clip ✓. If Clip ! appears, read the error; failed conversion deliberately leaves the clipboard unchanged. |

For a problem report, include the app version/build from About, macOS version, provider/server version and model, the action you took, and the menu error. Do not include API keys or private screenshots. [Report a problem](https://github.com/colombod/smart-clipboard/issues/new).

Accessibility support is still being validated. See the [current accessibility assessment](ACCESSIBILITY.md) for known limits and tested behavior.
