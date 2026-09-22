# Image-processing connections

This describes the 0.4 preview. All six routes are implemented and covered by adapter tests. Local oMLX has synthetic-image evidence and user-assisted region-capture use; cloud accounts and the full provider-specific native UAT remain unverified. The earlier 0.3.1 release includes only its original OpenAI API and ChatGPT/Codex connections.

## Configure once

Open Settings → Connection explicitly. Choose a provider, save its API key if required, and enter an image-capable model. **Refresh models** lists candidates; model listing alone does not establish image support. **Test image processing** sends a small generated test image through the selected connection and checks a value that appears only in its pixels. Provider charges or subscription usage can apply. This test does not use or store your captures or modify your clipboard.

Each provider keeps its own settings and Keychain entry. OpenAI's existing saved key, model, and ChatGPT/Codex configuration are preserved. Changing the provider, model, address or credential invalidates the displayed test result. A server or model changed outside the app requires another explicit test. No connection test runs automatically at startup or during capture.

Auto detect chooses the output format, not the provider. The connection, model, format and direction are fixed when a capture starts. Pass through bypasses AI and credential access. Processing errors preserve the clipboard and stay in the menu bar; Settings never opens automatically. The app does not retry through a different provider.

## Supported connection routes

| Selection | Connection | Requirements |
| --- | --- | --- |
| OpenAI | Responses API | Your OpenAI API key and a model supporting images and structured output. |
| ChatGPT via Codex | Existing official CLI integration | ChatGPT login with Codex entitlement and a compatible CLI. Credentials remain managed by Codex. |
| Anthropic | Messages API | Claude API key and supported vision/structured-output model. |
| Google Gemini | Interactions API | Gemini API key, available model and applicable project/billing entitlement. |
| Perplexity | Agent API | Perplexity API key and an explicitly selected image-capable direct model. No search presets, tools or fallback models are requested. |
| Local / oMLX | OpenAI-style Chat Completions | An existing oMLX server, complete vision model, and structured-generation support. |

New cloud routes use API keys. A consumer chat subscription is not itself an API credential; plan benefits and API credits must be checked with the provider. A Perplexity model may be served through another model provider; the selected model identifier is retained in history.

## oMLX

Enter the actual server base address ending in `/v1`; the upstream default is `http://127.0.0.1:8000/v1`. The app does not start servers or download models. A locally configured port may differ. A complete vision model is required: a text-only model cannot process screenshots even if its name or model card suggests otherwise.

For another machine, enter its address and server API key. Plain HTTP is accepted only for loopback/private LAN addresses; use HTTPS for other remote hosts. Normal TLS verification remains enabled. Keys are tied to the configured server address; changing it requires saving the appropriate key for the new address. URLs containing credentials, query strings or fragments and HTTP redirects are rejected.

On macOS 15 or later, connecting to a server on your LAN may ask for Local Network access. Allow Smart Clipboard in System Settings → Privacy & Security → Local Network, then explicitly refresh or test the connection again. The app's transport exceptions cover local names and loopback/private-network addresses only. Plain HTTP sends the image and any server key without transport encryption, so use a trusted local network or HTTPS. Validate LAN access from the packaged app: successful Terminal tests do not establish the app's separate macOS permission.

oMLX requests disable tools, including server-configured MCP tools, and explicitly request grammar-backed structured output. If the server/model cannot enforce the schema, conversion fails rather than silently relaxing constraints. Model/version compatibility requires an actual image test. A cold model can take longer to load; conversion has a bounded timeout and can be cancelled. Offline operation requires the model to be available already and the configured server to be reachable.

Disable oMLX's server-side model fallback for a fixed-model workflow. Before each upload, Smart Clipboard checks that the selected model is still listed and refuses missing model IDs. oMLX may echo the requested model even after server-side substitution, so history records the requested model and leaves the effective model unverified.

The desktop app continues to target macOS 14+. oMLX hosting has its own OS, Apple Silicon and memory requirements; it can run on another compatible machine.

Current tested configuration: the unmodified official oMLX 0.7.0.dev2 prerelease resolves the structured-generation failure seen with 0.6.4. Both `mlx-community/Qwen3-VL-8B-Instruct-4bit` and the 32B variant read the tested text/tables, but manual review still fails Description and SVG fidelity; 32B also fails the strengthened canvas-ratio assertion. These are not accepted all-format configurations. See [the exact test evidence and reproduction instructions](testing/OMLX.md); older diagnostic-patch results are separate from the later packaged-server tests.

## Results, storage and verification

Every connection returns the same format/content envelope. The app rejects incomplete responses, tool requests, unexpected formats and invalid JSON/YAML before copying. HTML/SVG are editable source text, never rendered or executed. A syntactically valid result may still contain extraction mistakes.

History keeps the latest result for each format and records the producing provider and requested/effective model where known. Existing history remains readable. Reopening a result does not call a provider or replace the clipboard. Explicit reconversion uses the currently selected connection. User edits retain their original provenance and are marked edited.

Cloud conversions send the selected screenshot and instructions to that connection. Optional response/conversation storage is disabled where the API supports it; this is not a promise of zero provider retention. Keys and raw provider errors are not written to history. HTTP sessions avoid cookies, cache and redirects. Local image passthrough and on-device OCR remain available without cloud processing.

Live acceptance is tracked in Beads under `clip-cqc`, with the observable gates in [UAT.md](UAT.md). Adapter fixtures and a synthetic image test do not replace real global-shortcut → region/window selection → actual paste testing. Do not label a provider/model verified until those gates have recorded evidence.

## Primary references

- [OpenAI images](https://developers.openai.com/api/docs/guides/images-vision) and [structured output](https://developers.openai.com/api/docs/guides/structured-outputs).
- [Anthropic vision](https://platform.claude.com/docs/en/build-with-claude/vision), [structured output](https://platform.claude.com/docs/en/build-with-claude/structured-outputs), and [models](https://platform.claude.com/docs/en/api/models/list).
- [Gemini images](https://ai.google.dev/gemini-api/docs/image-understanding), [Interactions](https://ai.google.dev/gemini-api/docs/interactions-overview), and [structured output](https://ai.google.dev/gemini-api/docs/structured-output).
- [Perplexity images](https://docs.perplexity.ai/docs/agent-api/image-attachments), [output control](https://docs.perplexity.ai/docs/agent-api/output-control), and [search-free direct models](https://docs.perplexity.ai/docs/agent-api/migrate-from-sonar/how-to).
- [oMLX](https://github.com/jundot/omlx), [server implementation](https://github.com/jundot/omlx/blob/main/omlx/server.py), and [versioned releases](https://github.com/jundot/omlx/releases).
- [Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [local-network transport settings](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking), and [address-specific transport exceptions](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity/NSExceptionDomains).
