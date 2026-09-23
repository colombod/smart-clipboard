# Using Smart Clipboard

Smart Clipboard stays in the menu bar. Set your connection and preferred output once, then capture and paste into the app you are already using.

The current public release in the **0.4 preview** series is **[build 11](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.11)**. If you are using 0.3.1, the preview adds local oMLX, additional providers, About, notifications and update checks. See the [preview notes](releases/v0.4.0-preview.md) for current limitations.

**Development build 13 is not published yet.** It adds five interface languages, optional capture translation and local SVG tracing. Those sections below are explicitly labelled development; their controls are not available in the current public download.

## Install and start

Download the signed DMG from [GitHub Releases](https://github.com/colombod/smart-clipboard/releases), open it and drag **Smart Clipboard** into **Applications**. Eject the DMG and open the installed app. Look for **Clip** in the menu bar; no app window should open.

Open **Clip → Settings & Status** when you want to change a setting. Closing Settings leaves capture shortcuts working. **Clip → Quit Smart Clipboard** stops the app. Enable **Launch at login** in General if you want it to start with your Mac.

Official downloads are for Apple Silicon and macOS 14 or later. A local oMLX server has its own hardware and macOS requirements.

## Set up local image processing with oMLX

1. Install and start [oMLX](https://github.com/jundot/omlx), then download an image-capable model using its model downloader. See [Choose a local model](#choose-a-local-model) below for the exact IDs, download sizes and current test status. A text-only model cannot read screenshots.
2. Open Smart Clipboard **Settings → Connection** and select **Local / oMLX**.
3. Enter the server address shown by oMLX, ending in `/v1`. For example, a server on this Mac using port 8999 is `http://127.0.0.1:8999/v1`. The port must match your server; 8999 is not a universal default.
4. Click **Refresh models**, then choose the exact listed vision model. Our oMLX server lists the checkpoints as `Qwen3-VL-8B-Instruct-4bit` and `Qwen3-VL-32B-Instruct-4bit`; use the ID returned by your server rather than assuming it includes the `mlx-community/` download prefix.
5. If your server requires a key, enter it and click **Save key**. An unauthenticated server on this Mac needs no key. A server on another computer requires a key; use HTTPS outside a private local network.
6. Click **Test image processing**. This sends a generated sample image, not your screen or saved captures. A successful model listing alone does not prove image support.
7. In **General**, choose **Auto detect** or an explicit preferred output, then close Settings.

**Server compatibility:** oMLX 0.6.4 has a known bug affecting structured output from this vision model. Smart Clipboard rejects incomplete responses instead of copying them. The official [0.7.0.dev2 preview](https://github.com/jundot/omlx/releases/tag/v0.7.0.dev2) includes the upstream fix and was tested from its unmodified package. It remains a prerelease. Consult the [preview notes](releases/v0.4.0-preview.md) and [local test evidence](testing/OMLX.md) for the exact configuration; newer oMLX previews are not automatically covered. Merely installing a larger model does not fix this server bug.

oMLX must remain running while you use AI extraction. Smart Clipboard connects to it; it does not start the server, download models or switch to a cloud service if local processing fails. With the server on `127.0.0.1`, captures are sent to this Mac. A remote server receives the selected capture.

### Choose a local model

The following are 4-bit MLX Community conversions of Qwen image-capable models. Copy the full download ID into oMLX's downloader:

| Download ID and model card | Disk download | Status on 22 September 2026 |
| --- | --- | --- |
| [mlx-community/Qwen3-VL-8B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit) | About 5.78 GB in the [publisher's file listing](https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit/tree/main). | Smaller starting point for local evaluation. Text, tables and structured data worked on tested synthetic images; Description invented spelling observations and SVG changed aspect ratio, borders or layout. It has not passed all-format quality acceptance. |
| [mlx-community/Qwen3-VL-32B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen3-VL-32B-Instruct-4bit) | Verified download: 19,636,446,591 bytes across 19 files, about 19.64 GB / 18.29 GiB. | Tested with oMLX 0.7.0.dev2. It preserved the test values, but Description invented alignment details and SVG used the wrong canvas and added a table row. Six prompt probes improved canvas dimensions without resolving content/layout errors. It has not passed all-format quality acceptance. |

The measured 32B download matches [publisher revision `6e5644d`](https://huggingface.co/mlx-community/Qwen3-VL-32B-Instruct-4bit/tree/6e5644d3ea4b953b5221ffd02339bf897041038a). Sizes describe disk downloads, not running memory use.

**Memory planning estimates:** allow at least 16 GB unified memory for the 8B candidate or 48 GB for 32B, with additional headroom for larger images, context and other apps. These are conservative estimates, not verified minimum requirements or speed guarantees. The recorded tests used a 128 GiB Mac; lower-memory Macs have not been validated. Keep extra disk space available for server caches. Start with a small non-private sample and check the output before relying on either model.

For observed outputs and the distinction between automated checks and visual quality, see [the local test evidence](testing/OMLX.md). Description and SVG remain experimental in this preview and have not passed all-format quality acceptance.

## Choose another connection

For **OpenAI**, **Anthropic**, **Google Gemini** or **Perplexity**:

1. Choose the provider in **Settings → Connection**.
2. Enter that provider's API key in **New API key**, then click **Save key**. Approve macOS Keychain access if requested.
3. Click **Refresh models**, use **Choose a listed model**, or enter an image-capable model available to your account. A listed model may still lack the required image or structured-output capability.
4. Click **Test image processing** and wait for the success message before capturing.

API access and billing are separate from consumer chat subscriptions. Each provider keeps its own saved key and settings. Changing a provider or model does not change your preferred output. Cloud routes have request/response tests, but have not all been verified against live accounts in this preview; see [connection test status](PROVIDERS.md).

For **ChatGPT via Codex**, use the **Install / update Codex CLI** link in Connection, then **Sign in with ChatGPT** and complete the official sign-in flow. Leave **Codex executable** blank for automatic discovery unless you installed it in a custom location. The model is optional. Run **Test image processing** after signing in. This requires an account with Codex access and a compatible official CLI; subscription usage limits apply. Credentials stay with Codex.

If an existing saved key needs approval after an update, click **Authorize saved key** explicitly. Background capture never opens a Keychain dialog for you. Never put API keys into issue reports or screenshots shared for support.

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

All AI outputs, including HTML and SVG, are copied as text. The app does not render or execute generated markup. **Default direction** adds an instruction to subsequent captures, for example “Preserve table columns.” AI output can contain mistakes; our small local model has known Description and SVG quality limitations documented in the [preview notes](releases/v0.4.0-preview.md).

## Trace a picture to SVG

**Development build 13:** the following controls are not in the published preview build 11. Native capture and installation acceptance must finish before this feature is advertised as released.

SVG has two methods:

| Method | When to use it | What it needs |
| --- | --- | --- |
| **Reconstruct with AI** | Ask your model to rebuild a diagram or illustration as vector source. It can interpret instructions, but may change or invent details. This remains the default, including after upgrading. | Your configured AI connection. |
| **Trace on device** | Follow the visible shapes and colours of a photo, logo or line drawing. The result is an approximation made of vector shapes. | The helper included with Smart Clipboard. No AI connection, API key, model download, server or additional installation. |

To make local tracing your everyday capture result:

1. Open **Settings → General** and set **Preferred format** to **SVG**.
2. Set **SVG method** to **Trace on device**.
3. Choose a **Trace preset**: **Photo** for pictures with many colours, **Logo** for logos and flat artwork, or **Line drawing** for drawings with clear lines.
4. Choose **Balanced** detail to start. **Detailed** preserves more shapes and colours, with larger files.
5. Close Settings. Use your normal rectangle or window shortcut, wait for **Clip ✓** or the ready notification, then paste.

These choices are saved; capture does not open a method or preset chooser. **Clip …** shows that processing is in progress. Ready notifications follow your notification settings and are sent only after copying. Failure leaves the previous clipboard contents in place and reports through the menu and configured failure notification. Cancelling stays quiet and also preserves the clipboard.

The clipboard contains **SVG source text**, rather than an image attachment. To use the result as artwork, open the result from History, choose **Save…** and save an `.svg` file, then open or import it in your vector editor. Pasting into a text editor shows the SVG code; whether another app accepts pasted SVG source depends on that app. Large SVGs are kept out of Smart Clipboard’s text editor so it stays responsive; you can still copy or save them.

Tracing stays on this Mac and uses the bundled [VTracer](https://github.com/visioncortex/vtracer) helper. It keeps the background and makes visible words into vector outlines; the words are not editable text. **Default direction** and **Output language** do not change a local trace. Choose AI reconstruction or text extraction when you need language processing. Automatic background removal and recovery of accurate chart data are not included. A traced chart is a picture made of shapes, not a data table or a guarantee of accurate values.

For an earlier screenshot, open **Clip → History**, select the capture, choose **SVG** and **Trace on device**, adjust the preset and detail, then choose **Trace to SVG**. Use **Copy** when you want the result on your clipboard, or enable **Copy after manual conversion**. Simply opening History never changes the clipboard. **Saved formats** keeps local traces by preset and detail, alongside your AI versions; reopening one does not process the image again. You can return to **Reconstruct with AI** when you want the model to interpret the original image instead.

## Languages and translation

**Development build 13:** these interface languages and translation controls are not in the published preview build 11.

The interface follows your Mac’s preferred supported language: English, Italian, Spanish, French or German, with English as the fallback. This includes menus, settings, notifications and accessibility labels. Restart Smart Clipboard after changing its language in macOS. Provider names, your captures and model identifiers are kept as they are.

Captured content has its own language setting. In **Settings → General → Languages → Capture output**, choose:

| Choice | What happens on the next AI capture |
| --- | --- |
| **Keep source language** (default) | Text stays in the language or languages detected in the image, even when your Mac uses another language. |
| **System language** | Human-readable content is translated into your Mac’s preferred language. |
| **A specific language** | Human-readable content is translated into that language, independently of your Mac and the app interface. |

An explicit language choice takes priority over conflicting translation requests in **Default direction**. When upgrading with existing directions, **Use saved directions** keeps their previous behavior until you choose a language. Older saved results with directions retain that choice too. Select **Keep source language** to stop translation, or select a target to use the new controls. The language and other capture preferences are fixed when an operation starts; changing Settings affects the next operation.

Translation uses your selected AI connection, including local oMLX, and its quality depends on the model and source image. Code, identifiers, numbers and structured syntax are requested to stay intact. **Pass through** always copies the original image without AI. **Extract text on device** reads the source language and does not translate. For descriptions without readable text, the source-language mode uses English; choose a target language if you want a different one.

## Completion and failure notifications

Open **Settings → General → Capture notifications** and click **Enable notifications**. Allow Smart Clipboard's macOS notification request. This is an explicit setup step; launching the app or taking a capture never triggers that permission prompt automatically.

Choose **When a capture is ready to paste**, **When capture or conversion fails**, or both. **Play a notification sound** is optional and starts off. A successful notification is sent only after the result has been copied. Pass-through images also receive a ready notification. Cancelling selection or processing stays quiet; a manual conversion without automatic copying does not claim the result is ready to paste.

The banner shows only a status and output format, never your screenshot, extracted text or detailed provider error. Click it to open Smart Clipboard explicitly. Posting it does not open the app or take focus. **Turn off notifications** disables them in the app; **Open notification settings** lets you choose macOS banner/alert style and sound permissions. Focus modes may hide or silence alerts. The Clip menu always keeps its status indicator.

If **Clip ✓** appears but you see no notification or hear no sound, macOS may be suppressing alerts while your display is being shared, mirrored or recorded. Taking a screenshot is different from an ongoing sharing or recording session: Smart Clipboard’s Screen Recording permission does not mean it continuously records your screen. Stop any ongoing sharing or recording session, then try another capture. Also check whether a Focus, such as Sleep, is active—including one synced from another device. Smart Clipboard respects these macOS policies. Allowing notifications during screen sharing is a system-wide choice that can reveal other apps’ notifications to viewers; it is not required for normal capture and is not the recommended first troubleshooting step.

## Reuse a previous capture

Choose **Clip → History**, open a capture, select another format, and click **Convert with AI**. The original image is reused. **Saved formats** retrieves an existing result without another AI request. Opening history does not copy anything automatically; use **Copy**, or enable **Copy after manual conversion**. **Extract text on device** uses Apple's local text recognition and returns source-language plain text without an AI connection.

**Development build 13** adds **Output language** and separate saved versions for each format and language. For example, a Spanish capture can have separate Spanish, English and French plain-text results. Repeating the same format and language replaces only that version; other language versions remain saved. **Saved formats** identifies the format and language. The same development build also supports [local SVG traces](#trace-a-picture-to-svg), saved by preset and detail.

In **Settings → History**, choose the maximum number of saved clips and apply the limit. The default is 50; the maximum is 500. Oldest clips are removed first. Zero clears and disables history. You can delete one clip or clear all history. Deletion does not remove exported files or change what is already on the system clipboard.

History stores your selected/imported images and results locally. It does not watch other apps' clipboard activity.

## Privacy and storage

The app captures a selected region or window only when you ask; it does not continuously watch your screen or other apps' clipboard contents. AI processing sends the image and your instructions to the connection you selected. A local oMLX server on `127.0.0.1` processes it on this Mac; a server on another computer receives it there. Cloud data handling follows that provider's account policies. Turning off optional response storage is not a promise of zero provider retention.

**Pass through (image)** makes no AI request. The editor's **Extract text on device** uses Apple's local text recognition. API keys are stored in macOS Keychain; ChatGPT credentials remain with Codex.

History stores originals and results in `~/Library/Application Support/Smart Clipboard/History/`. Files are restricted to your Mac user, but the app does not separately encrypt them. Set the history limit to zero to clear existing entries and stop saving new ones. Exported files and clipboard contents are independent of history. Notification messages never contain capture contents.

## Updates

Updater-enabled releases provide **Check for Updates…** in the Clip menu and About page. Enable daily background checks in About if desired. An available update is indicated in the menu without opening a window. Select it to review and install; capture or conversion must finish first.

Stable releases are the default. In About, set **Releases → Stable and preview releases** only if you want development previews. A preview can include known limitations listed in its release notes. Updates keep your preferences and saved history. They do not change your selected AI connection.

Older releases without an updater need one manual replacement with an updater-enabled release. Quit the old app before dragging the new one into Applications. Keep using official signed downloads.

## If capture does not work

| Symptom | Check |
| --- | --- |
| No Clip menu | Open the installed app. A crowded menu bar may hide items. |
| Shortcut does nothing | Open Settings → Shortcuts and check permission and each shortcut's registration status. Record another shortcut or use Find available shortcuts if there is a conflict. |
| Screen access says “needed” even though its macOS switch is on | Quit and reopen Smart Clipboard first. After replacing an old ad-hoc development build with a signed release, macOS can retain approval for the old signature. Refresh only Smart Clipboard's permission; see the recovery guidance below. |
| Local server unavailable | Start oMLX and confirm the address and port in Connection. |
| Model unavailable | Refresh models and select the exact installed vision model. |
| Repeated text or unfinished conversion | Check the oMLX version; 0.6.4 has the structured-output bug described above. |
| Capture copied an image | Preferred format is Pass through; select Auto detect or another format for extraction. |
| Pasting shows the previous item | Wait for Clip ✓. If Clip ! appears, read the error; failed conversion deliberately leaves the clipboard unchanged. |

**Old development-build permission:** in System Settings → Privacy & Security → Screen & System Audio Recording, switch only Smart Clipboard off and on, accepting Quit & Reopen when offered. If the warning persists, the old permission entry may need removing and the current `/Applications/Smart Clipboard.app` adding again with the **+** button. If macOS will not remove the entry, seek support for a reset scoped to this app; do not reset every application's permissions. The app never performs that reset automatically. Saved settings and history are separate from this macOS approval.

For a problem report, include the app version/build from About, macOS version, provider/server version and model, the action you took, and the menu error. Do not include API keys or private screenshots. [Report a problem](https://github.com/colombod/smart-clipboard/issues/new).

Accessibility support is still being validated. See the [current accessibility assessment](ACCESSIBILITY.md) for known limits and tested behavior.
