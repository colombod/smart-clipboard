# Language checks

Development verification on 23 September 2026 covers the language feature. It does not replace the installed-app acceptance gates in [UAT](../UAT.md).

## Interface

English, Italian, Spanish, French and German each contain all 422 UI keys and both macOS permission descriptions. `scripts/check-localizations.py` checks missing/extra keys, duplicate entries and positional arguments; its `--app` option also compares the assembled app's resources with the source catalogs. CI runs the checker and its parser tests.

Windowless SwiftUI snapshots cover General settings, the capture editor and history in light/dark mode for each language. Inspection caught an untranslated native language name and truncated Italian image-action labels; both were corrected. These snapshots cannot prove native menu drawing, scrolling, VoiceOver pronunciation or actual notification presentation. Those remain part of D07.

## Capture languages

The automated suite covers default source preservation, explicit/system targets, preference snapshots, manual copy behavior, failures, image pass-through, source-only OCR, old settings/history migration and distinct saved language variants. New source-language entries explicitly encode their policy, so reopening them cannot mistake ordinary directions for an older translation setting.

An opt-in live test used the existing local oMLX server and **Qwen3-VL-8B-Instruct-4bit** with a generated Spanish image. The initial prompt sometimes retained Spanish for an English target; the plain-text instruction was corrected to allow requested translation explicitly. The subsequent test passed and its outputs were inspected:

| Requested behavior | Observed result |
| --- | --- |
| Keep source language | Spanish text and the visible code were preserved. |
| System language (injected `en-GB`) | English translation, with the visible code preserved. |
| French from history | French translation, with Spanish and English versions still saved. |
| Manual copy disabled | Translation did not overwrite the private test clipboard. |

The [synthetic source](evidence/languages-2026-09-23/spanish-source.png), [source-language output](evidence/languages-2026-09-23/source.txt), [English](evidence/languages-2026-09-23/english.txt) and [French](evidence/languages-2026-09-23/french.txt) are retained for inspection. Only synthetic content was used; the test never reads the screen or the general clipboard. This is a small plain-text sample, not a claim that every offered target or provider has been validated. Translation quality remains model-dependent.

## Reproduce

```sh
bash scripts/test.sh
python3 Tests/ReleaseScripts/test-localizations.py
python3 scripts/check-localizations.py

# Optional: only a configured, unauthenticated local test server; synthetic content.
SMART_CLIPBOARD_LANGUAGE_TEST_URL=http://127.0.0.1:8999/v1 \
SMART_CLIPBOARD_LANGUAGE_TEST_MODEL=Qwen3-VL-8B-Instruct-4bit \
swift test --disable-sandbox --filter LanguageLiveTests

# Run separately, one locale per process. No app window is shown.
SMART_CLIPBOARD_LANGUAGE_RENDER=it \
SMART_CLIPBOARD_LANGUAGE_RENDER_DIR=/tmp/smart-clipboard-language-renders \
swift test --disable-sandbox --filter translatedLanguageScreens

BUILD_OUTPUT_DIR=/tmp/smart-clipboard-language-package bash scripts/build-app.sh
python3 scripts/check-localizations.py \
  --app '/tmp/smart-clipboard-language-package/Smart Clipboard.app'
```

The render language override is confined to the test process. Production settings, shortcuts, history and clipboard are not modified.
