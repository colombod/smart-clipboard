import Foundation

public struct PerplexityAdapter: ImageProviderAdapter {
    public init() {}

    public func request(profile: ConnectionProfile, png: Data, key: String, format: OutputFormat, instruction: String) throws -> URLRequest {
        try ProviderWire.requireImage(png, maximumBytes: 50 * 1024 * 1024)
        let model = try ProviderWire.requireModel(profile)
        try requireKey(key)
        // A direct model is essential: presets retain their search tools even with tools: [].
        return try ProviderWire.request(url: URL(string: "https://api.perplexity.ai/v1/agent")!, key: key, body: [
            "model": model,
            "instructions": ConversionProtocol.prompt(format: format, instruction: instruction),
            "input": [["role": "user", "content": [
                ["type": "input_text", "text": "Convert this screenshot using the requested format."],
                ["type": "input_image", "image_url": "data:image/png;base64," + png.base64EncodedString()]
            ]]],
            "tools": [],
            "store": false,
            "stream": false,
            "max_output_tokens": 12000,
            "response_format": ["type": "json_schema", "json_schema": [
                "name": "ClipboardExtraction", "schema": ProviderWire.schema(for: format)
            ]]
        ])
    }

    public func response(_ data: Data) throws -> ProviderResponse {
        let body = try LocalPerplexityResponse.object(data)
        guard body["status"] as? String == "completed",
              !LocalPerplexityResponse.present(body["incomplete_details"]),
              LocalPerplexityResponse.emptyArray(body["tools"]),
              let output = body["output"] as? [[String: Any]], !output.isEmpty else {
            throw ClipError.message("Perplexity did not finish the conversion without tools. Try a smaller capture or another image-capable model.")
        }
        if let usage = body["usage"] as? [String: Any],
           let calls = usage["tool_calls_details"] as? [String: Any], !calls.isEmpty {
            throw ClipError.message("Perplexity unexpectedly used tools. The clipboard was not changed.")
        }
        var pieces: [String] = []
        var messageCount = 0
        for item in output {
            if let status = item["status"] as? String, status != "completed" {
                throw ClipError.message("Perplexity returned an unfinished conversion. Try again.")
            }
            switch item["type"] as? String {
            case "reasoning": continue
            case "message":
                messageCount += 1
                guard item["role"] as? String == "assistant",
                      let content = item["content"] as? [[String: Any]], !content.isEmpty else {
                    throw ClipError.message("Perplexity returned no usable conversion.")
                }
                for part in content {
                    guard part["type"] as? String == "output_text", let text = part["text"] as? String else {
                        throw ClipError.message("Perplexity could not return the requested conversion.")
                    }
                    pieces.append(text)
                }
            default:
                throw ClipError.message("Perplexity returned an unexpected tool result. The clipboard was not changed.")
            }
        }
        guard messageCount == 1 else { throw ClipError.message("Perplexity returned an ambiguous conversion. Try again.") }
        let text = pieces.joined()
        try LocalPerplexityResponse.validateEnvelope(text)
        return ProviderResponse(text: text, model: body["model"] as? String)
    }

    public func modelsRequest(profile: ConnectionProfile, key: String) throws -> URLRequest {
        try requireKey(key)
        return try ProviderWire.request(url: URL(string: "https://api.perplexity.ai/v1/models")!, key: key)
    }

    public func modelsResponse(_ data: Data) throws -> [ProviderModel] {
        // The catalog identifies models but does not promise image support for every entry.
        try ProviderWire.listedModels(data)
    }

    private func requireKey(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClipError.message("Add a Perplexity API key in Settings → Connection.")
        }
    }
}
