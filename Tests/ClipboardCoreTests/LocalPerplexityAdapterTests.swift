import Foundation
import Testing
@testable import ClipboardCore

struct LocalPerplexityAdapterTests {
    private let envelope = #"{"format":"text","content":"Visible words"}"#
    private let png = Data([1, 2, 3])

    @Test func localImageRequestRequiresGrammarAndDisablesServerTools() throws {
        let request = try OMLXAdapter().request(profile: .init(provider: .omlx, model: "my-vision-model"), png: png, key: "", format: .markdown, instruction: "Keep headings")
        #expect(request.url?.absoluteString == "http://127.0.0.1:8000/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try payload(request)
        #expect(body["model"] as? String == "my-vision-model")
        #expect(body["tool_choice"] as? String == "none")
        #expect(body["temperature"] as? Double == 0)
        #expect((body["tools"] as? [Any])?.isEmpty == true)
        #expect(body["response_format"] == nil)
        #expect((body["structured_outputs"] as? [String: Any])?["json"] as? [String: Any] != nil)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect((messages[0]["content"] as? String)?.contains("untrusted data") == true)
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        #expect((parts.first?["text"] as? String)?.contains("The format must be markdown") == true)
        #expect((parts.first?["text"] as? String)?.contains("Keep headings") == true)
        #expect((parts.last?["image_url"] as? [String: Any])?["url"] as? String == "data:image/png;base64,AQID")
    }

    @Test func perplexityUsesNativeImageSchemaAndNoSearchPreset() throws {
        let request = try PerplexityAdapter().request(profile: .init(provider: .perplexity, model: "openai/vision-model", endpoint: "https://unrelated.example"), png: png, key: "pplx-test", format: .json, instruction: "Read every row")
        #expect(request.url?.absoluteString == "https://api.perplexity.ai/v1/agent")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pplx-test")
        let body = try payload(request)
        #expect(body["model"] as? String == "openai/vision-model")
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] as? Bool == false)
        #expect((body["tools"] as? [Any])?.isEmpty == true)
        for forbidden in ["preset", "profile", "models", "skills", "previous_response_id", "text", "disable_search"] {
            #expect(body[forbidden] == nil)
        }
        let schema = try #require(body["response_format"] as? [String: Any])
        #expect(schema["type"] as? String == "json_schema")
        #expect((schema["json_schema"] as? [String: Any])?["name"] as? String == "ClipboardExtraction")
        let input = try #require(body["input"] as? [[String: Any]])
        let parts = try #require(input.first?["content"] as? [[String: Any]])
        #expect(parts.last?["type"] as? String == "input_image")
        #expect(parts.last?["image_url"] as? String == "data:image/png;base64,AQID")
    }

    @Test(arguments: [
        "http://localhost:8000", "http://127.0.0.1:8000/v1/", "http://[::1]:8000/v1",
        "http://192.168.1.20:8000/v1", "http://10.0.0.8:8000/v1", "http://172.16.0.3:8000/v1",
        "http://studio.local:8000/v1", "http://[fd00::10]:8000/v1", "https://inference.example/v1"
    ])
    func acceptsExplicitLocalOrSecureServer(_ endpoint: String) throws {
        let request = try OMLXAdapter().modelsRequest(profile: .init(provider: .omlx, endpoint: endpoint), key: "server-key")
        #expect(request.url?.path == "/v1/models")
    }

    @Test(arguments: [
        "https://user:secret@studio.local/v1", "https://user@studio.local/v1", "http://localhost:8000/v1?key=secret",
        "http://localhost:8000/v1#part", "file:///tmp/server", "http://public.example/v1", "http://8.8.8.8/v1",
        "http://172.32.0.1:8000/v1", "http://localhost.attacker.example:8000/v1", "http://127.0.0.1.attacker.example/v1",
        "http://localhost:8000/v1/chat/completions", "http://localhost:8000/%76%31", "http://localhost:0/v1"
    ])
    func rejectsUnsafeOrAmbiguousEndpoint(_ endpoint: String) {
        #expect(throws: (any Error).self) {
            try OMLXAdapter().modelsRequest(profile: .init(provider: .omlx, endpoint: endpoint), key: "key")
        }
    }

    @Test func otherComputerRequiresServerCredential() {
        #expect(throws: (any Error).self) {
            try OMLXAdapter().modelsRequest(profile: .init(provider: .omlx, endpoint: "http://studio.local:8000/v1"), key: "")
        }
    }

    @Test(arguments: ["", " ", "\n\t"])
    func clearedLocalEndpointNeverFallsBackToDefault(_ endpoint: String) {
        var profile = ConnectionProfile(provider: .omlx, model: "vision-model")
        profile.endpoint = endpoint
        #expect(throws: (any Error).self) { try OMLXAdapter().modelsRequest(profile: profile, key: "") }
        #expect(throws: (any Error).self) {
            try OMLXAdapter().request(profile: profile, png: png, key: "", format: .text, instruction: "")
        }
    }

    @Test func missingConfigurationNeverConstructsConversion() {
        #expect(throws: (any Error).self) {
            try OMLXAdapter().request(profile: .init(provider: .omlx), png: png, key: "", format: .text, instruction: "")
        }
        #expect(throws: (any Error).self) {
            try PerplexityAdapter().request(profile: .init(provider: .perplexity, model: "vision"), png: png, key: " ", format: .text, instruction: "")
        }
        #expect(throws: (any Error).self) {
            try OMLXAdapter().request(profile: .init(provider: .omlx, model: "vision"), png: Data(), key: "", format: .text, instruction: "")
        }
    }

    @Test func completeLocalResponseRetainsModel() throws {
        let result = try OMLXAdapter().response(json(localReply()))
        #expect(result == ProviderResponse(text: envelope, model: "local-vision"))
    }

    @Test(arguments: ["length", "tool_calls", "content_filter", "error", ""])
    func incompleteLocalChoiceIsRejected(_ finish: String) throws {
        #expect(throws: (any Error).self) { try OMLXAdapter().response(json(localReply(finish: finish))) }
    }

    @Test func localToolOutputAndMultipleChoicesAreRejected() throws {
        var reply = localReply()
        reply["choices"] = [["finish_reason": "stop", "message": ["role": "assistant", "content": envelope, "tool_calls": [["type": "function"]]]]]
        #expect(throws: (any Error).self) { try OMLXAdapter().response(json(reply)) }
        let choice = try #require((localReply()["choices"] as? [[String: Any]])?.first)
        reply["choices"] = [choice, choice]
        #expect(throws: (any Error).self) { try OMLXAdapter().response(json(reply)) }
    }

    @Test func completePerplexityResponseSeparatesReasoningAndContent() throws {
        var reply = perplexityReply()
        reply["output"] = [["type": "reasoning", "summary": []], ["type": "message", "role": "assistant", "status": "completed", "content": [
            ["type": "output_text", "text": #"{"format":"text","#],
            ["type": "output_text", "text": #""content":"Visible words"}"#]
        ]]]
        #expect(try PerplexityAdapter().response(json(reply)) == ProviderResponse(text: envelope, model: "openai/vision-model"))
    }

    @Test(arguments: ["incomplete", "queued", "in_progress", "failed", "cancelled", ""])
    func incompletePerplexityResponseIsRejected(_ status: String) throws {
        var reply = perplexityReply()
        reply["status"] = status
        #expect(throws: (any Error).self) { try PerplexityAdapter().response(json(reply)) }
    }

    @Test(arguments: ["web_search_call", "search_results", "function_call", "mcp_call", "fetch_url_call"])
    func perplexityToolItemsAreRejected(_ type: String) throws {
        var reply = perplexityReply()
        var items = try #require(reply["output"] as? [[String: Any]])
        items.insert(["type": type, "status": "completed"], at: 0)
        reply["output"] = items
        #expect(throws: (any Error).self) { try PerplexityAdapter().response(json(reply)) }
    }

    @Test func perplexityPartialMessageRefusalAndToolUsageAreRejected() throws {
        var reply = perplexityReply()
        reply["output"] = [["type": "message", "role": "assistant", "status": "incomplete", "content": [["type": "output_text", "text": envelope]]]]
        #expect(throws: (any Error).self) { try PerplexityAdapter().response(json(reply)) }
        reply["output"] = [["type": "message", "role": "assistant", "content": [["type": "refusal", "refusal": "Cannot comply"]]]]
        #expect(throws: (any Error).self) { try PerplexityAdapter().response(json(reply)) }
        reply = perplexityReply()
        reply["usage"] = ["tool_calls_details": ["search_web": ["invocation": 1]]]
        #expect(throws: (any Error).self) { try PerplexityAdapter().response(json(reply)) }
        reply = perplexityReply()
        reply["incomplete_details"] = ["reason": "max_output_tokens"]
        #expect(throws: (any Error).self) { try PerplexityAdapter().response(json(reply)) }
    }

    @Test(arguments: [
        "plain prose", "{}", #"{"format":"text","content":""}"#, #"{"format":"text","content":"a","extra":true}"#,
        #"{"format":"image","content":"a"}"#, #"{"format":"json","content":"{broken}"}"#,
        "```json\n{\"format\":\"text\",\"content\":\"a\"}\n```"
    ])
    func bothProvidersRejectInvalidExtractionEnvelopes(_ text: String) throws {
        #expect(throws: (any Error).self) { try OMLXAdapter().response(json(localReply(text: text))) }
        #expect(throws: (any Error).self) { try PerplexityAdapter().response(json(perplexityReply(text: text))) }
    }

    @Test func responseSizeIsBounded() throws {
        let large = String(repeating: "x", count: 1024 * 1024)
        let text = String(decoding: try json(["format": "text", "content": large]), as: UTF8.self)
        #expect(throws: (any Error).self) { try OMLXAdapter().response(json(localReply(text: text))) }
        #expect(throws: (any Error).self) { try PerplexityAdapter().response(Data(repeating: 32, count: 2 * 1024 * 1024 + 1)) }
    }

    @Test func modelDiscoveryDoesNotInventVisionCapability() throws {
        let list = try json(["data": [["id": "z-vision-name"], ["id": "a-model"]]])
        let expected = [ProviderModel(id: "a-model"), ProviderModel(id: "z-vision-name")]
        #expect(try OMLXAdapter().modelsResponse(list) == expected)
        #expect(try PerplexityAdapter().modelsResponse(list) == expected)
        let request = try PerplexityAdapter().modelsRequest(profile: .init(provider: .perplexity), key: "key")
        #expect(request.url?.absoluteString == "https://api.perplexity.ai/v1/models")
        #expect(request.httpMethod == "GET")
    }

    private func payload(_ request: URLRequest) throws -> [String: Any] {
        try ProviderWire.json(#require(request.httpBody))
    }

    private func json(_ body: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: body)
    }

    private func localReply(text: String? = nil, finish: String = "stop") -> [String: Any] {
        ["model": "local-vision", "choices": [["finish_reason": finish, "message": ["role": "assistant", "content": text ?? envelope]]]]
    }

    private func perplexityReply(text: String? = nil) -> [String: Any] {
        ["model": "openai/vision-model", "status": "completed", "error": NSNull(), "output": [
            ["type": "message", "role": "assistant", "status": "completed", "content": [["type": "output_text", "text": text ?? envelope]]]
        ]]
    }
}
