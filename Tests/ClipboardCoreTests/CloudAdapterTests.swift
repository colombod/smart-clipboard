import Foundation
import Testing
@testable import ClipboardCore

@Suite(.serialized)
struct CloudAdapterTests {
    private let png = Data([1, 2, 3])
    private let key = "test-key-keep-out-of-URLs"

    @Test func anthropicRequestUsesMessagesImageAndStructuredSchema() throws {
        let profile = ConnectionProfile(provider: .anthropic, model: "vision-test", endpoint: "https://untrusted.invalid")
        let request = try AnthropicAdapter().request(profile: profile, png: png, key: key, format: .yaml, instruction: "Translate to Italian")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try ProviderWire.json(#require(request.httpBody))
        #expect(body["model"] as? String == "vision-test")
        #expect(body["max_tokens"] as? Int == 12000)
        #expect(body["tools"] == nil)
        #expect(body["cache_control"] == nil)
        let prompt = try #require(body["system"] as? String)
        #expect(prompt.contains("Translate to Italian"))
        #expect(prompt.contains("untrusted data"))
        #expect(prompt.contains("format must be yaml"))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let blocks = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(blocks.first?["type"] as? String == "image")
        let image = try #require(blocks.first?["source"] as? [String: Any])
        #expect(image["type"] as? String == "base64")
        #expect(image["media_type"] as? String == "image/png")
        #expect(image["data"] as? String == "AQID")
        let config = try #require(body["output_config"] as? [String: Any])
        let format = try #require(config["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        try expectConversionSchema(format["schema"])
    }

    @Test func geminiRequestUsesStatelessInteractionsAndHeaderCredential() throws {
        let profile = ConnectionProfile(provider: .google, model: "models/vision-test", endpoint: "https://untrusted.invalid")
        let request = try GeminiAdapter().request(profile: profile, png: png, key: key, format: .json, instruction: "Preserve names")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == key)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.query == nil)
        let body = try ProviderWire.json(#require(request.httpBody))
        #expect(body["model"] as? String == "vision-test")
        #expect(body["store"] as? Bool == false)
        #expect(body["tools"] == nil)
        #expect(body["previous_interaction_id"] == nil)
        #expect(body["background"] == nil)
        let prompt = try #require(body["system_instruction"] as? String)
        #expect(prompt.contains("Preserve names"))
        #expect(prompt.contains("untrusted data"))
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.first?["type"] as? String == "image")
        #expect(input.first?["mime_type"] as? String == "image/png")
        #expect(input.first?["data"] as? String == "AQID")
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "text")
        #expect(format["mime_type"] as? String == "application/json")
        try expectConversionSchema(format["schema"])
    }

    @Test func anthropicReadsFinalTextAndOmitsThinking() throws {
        let data = Data(#"{"type":"message","role":"assistant","model":"actual-model","stop_reason":"end_turn","content":[{"type":"thinking","thinking":"private"},{"type":"redacted_thinking","data":"opaque"},{"type":"text","text":"hello "},{"type":"text","text":"world"}]}"#.utf8)
        #expect(try AnthropicAdapter().response(data) == ProviderResponse(text: "hello world", model: "actual-model"))
    }

    @Test(arguments: ["refusal", "max_tokens", "tool_use", "pause_turn", "stop_sequence", "model_context_window_exceeded"])
    func anthropicRejectsNonFinalStops(_ stop: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["type": "message", "role": "assistant", "stop_reason": stop, "content": [["type": "text", "text": "partial"]]])
        #expect(throws: (any Error).self) { try AnthropicAdapter().response(data) }
    }

    @Test(arguments: ["tool_use", "server_tool_use", "web_search_tool_result", "refusal", "unknown"])
    func anthropicRejectsUnsupportedBlocksAlongsideText(_ type: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["type": "message", "role": "assistant", "stop_reason": "end_turn", "content": [["type": "text", "text": "partial"], ["type": type]]])
        #expect(throws: (any Error).self) { try AnthropicAdapter().response(data) }
    }

    @Test func anthropicDoesNotExposeRefusalDetails() throws {
        let data = Data(#"{"type":"message","role":"assistant","stop_reason":"end_turn","stop_details":{"type":"refusal","explanation":"private screenshot data"},"content":[{"type":"text","text":"private screenshot data"}]}"#.utf8)
        do {
            _ = try AnthropicAdapter().response(data)
            Issue.record("Expected the refusal to be rejected")
        } catch {
            #expect(!error.localizedDescription.contains("private screenshot data"))
        }
    }

    @Test func geminiReadsModelOutputAndOmitsThoughts() throws {
        let data = Data(#"{"object":"interaction","status":"completed","model":"actual-model","steps":[{"type":"thought","summary":[{"type":"text","text":"private"}]},{"type":"model_output","content":[{"type":"text","text":"hello "},{"type":"text","text":"world"}]}]}"#.utf8)
        #expect(try GeminiAdapter().response(data) == ProviderResponse(text: "hello world", model: "actual-model"))
    }

    @Test(arguments: ["in_progress", "requires_action", "incomplete", "failed", "cancelled", "budget_exceeded"])
    func geminiRejectsNonCompletedStatus(_ status: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": status, "steps": [["type": "model_output", "content": [["type": "text", "text": "partial"]]]]])
        #expect(throws: (any Error).self) { try GeminiAdapter().response(data) }
    }

    @Test(arguments: ["function_call", "function_result", "google_search_call", "url_context_call", "mcp_server_tool_call", "user_input", "unknown"])
    func geminiRejectsToolStepsAlongsideText(_ type: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": "completed", "steps": [["type": "model_output", "content": [["type": "text", "text": "partial"]]], ["type": type]]])
        #expect(throws: (any Error).self) { try GeminiAdapter().response(data) }
    }

    @Test func geminiRejectsRefusalAndDoesNotExposeProviderError() throws {
        let refusal = Data(#"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"refusal","text":"private screenshot data"}]}]}"#.utf8)
        #expect(throws: (any Error).self) { try GeminiAdapter().response(refusal) }
        let errorData = Data(#"{"status":"failed","error":{"code":"safety","message":"private screenshot data"}}"#.utf8)
        do {
            _ = try GeminiAdapter().response(errorData)
            Issue.record("Expected the provider error to be rejected")
        } catch {
            #expect(!error.localizedDescription.contains("private screenshot data"))
        }
    }

    @Test(arguments: ["", "not JSON", "{}", "[]"])
    func malformedResponsesAreRejected(_ payload: String) {
        let data = Data(payload.utf8)
        #expect(throws: (any Error).self) { try AnthropicAdapter().response(data) }
        #expect(throws: (any Error).self) { try GeminiAdapter().response(data) }
    }

    @Test func emptyAndMissingOutputAreRejected() {
        let anthropic = Data(#"{"type":"message","role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"  "}]}"#.utf8)
        let gemini = Data(#"{"status":"completed","steps":[{"type":"thought"}]}"#.utf8)
        #expect(throws: (any Error).self) { try AnthropicAdapter().response(anthropic) }
        #expect(throws: (any Error).self) { try GeminiAdapter().response(gemini) }
    }

    @Test func cloudRequestsRequireAModelAndImage() {
        for adapter in [AnthropicAdapter() as any ImageProviderAdapter, GeminiAdapter() as any ImageProviderAdapter] {
            #expect(throws: (any Error).self) { try adapter.request(profile: ConnectionProfile(provider: .anthropic), png: png, key: key, format: .text, instruction: "") }
            #expect(throws: (any Error).self) { try adapter.request(profile: ConnectionProfile(provider: .anthropic, model: "vision-test"), png: Data(), key: key, format: .text, instruction: "") }
        }
        #expect(throws: (any Error).self) { try GeminiAdapter().request(profile: ConnectionProfile(provider: .google, model: "models/"), png: png, key: key, format: .text, instruction: "") }
    }

    @Test func imageLimitsAccountForBase64Expansion() {
        let anthropicProfile = ConnectionProfile(provider: .anthropic, model: "vision-test")
        #expect(throws: (any Error).self) { try AnthropicAdapter().request(profile: anthropicProfile, png: Data(count: 7_500_001), key: key, format: .text, instruction: "") }
        let geminiProfile = ConnectionProfile(provider: .google, model: "vision-test")
        // These bytes alone encode to exactly 20 MB; JSON and prompt overhead must still reject the request.
        #expect(throws: (any Error).self) { try GeminiAdapter().request(profile: geminiProfile, png: Data(count: 15_000_000), key: key, format: .text, instruction: "") }
    }

    @Test func instructionsCountTowardTotalRequestLimit() {
        let profile = ConnectionProfile(provider: .google, model: "vision-test")
        #expect(throws: (any Error).self) { try GeminiAdapter().request(profile: profile, png: png, key: key, format: .text, instruction: String(repeating: "x", count: 20_000_000)) }
    }

    @Test func modelDiscoveryKeepsCredentialsInHeaders() throws {
        let anthropic = try AnthropicAdapter().modelsRequest(profile: ConnectionProfile(provider: .anthropic), key: key)
        #expect(anthropic.httpMethod == "GET")
        #expect(anthropic.url?.host == "api.anthropic.com")
        #expect(anthropic.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
        #expect(anthropic.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let gemini = try GeminiAdapter().modelsRequest(profile: ConnectionProfile(provider: .google), key: key)
        #expect(gemini.httpMethod == "GET")
        #expect(gemini.url?.host == "generativelanguage.googleapis.com")
        #expect(gemini.value(forHTTPHeaderField: "x-goog-api-key") == key)
        #expect(gemini.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(gemini.url?.absoluteString.contains(key) == false)
    }

    @Test func anthropicModelsPreserveKnownAndUnknownCapabilities() throws {
        let data = Data(#"{"data":[{"id":"vision","capabilities":{"image_input":{"supported":true}}},{"id":"unknown","capabilities":null},{"id":"text","capabilities":{"image_input":{"supported":false}}},{"id":"missing"}]}"#.utf8)
        #expect(try AnthropicAdapter().modelsResponse(data) == [ProviderModel(id: "missing"), ProviderModel(id: "text", imageInput: false), ProviderModel(id: "unknown"), ProviderModel(id: "vision", imageInput: true)])
    }

    @Test func geminiMethodsDoNotImplyVisionSupport() throws {
        let data = Data(#"{"models":[{"name":"models/z-model","supportedGenerationMethods":["generateContent"]},{"name":"models/a-model"},{"name":"models/"}]}"#.utf8)
        #expect(try GeminiAdapter().modelsResponse(data) == [ProviderModel(id: "a-model"), ProviderModel(id: "z-model")])
    }

    private func expectConversionSchema(_ value: Any?) throws {
        let schema = try #require(value as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(schema["required"] as? [String] == ["format", "content"])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(properties.keys) == Set(["format", "content"]))
    }
}
