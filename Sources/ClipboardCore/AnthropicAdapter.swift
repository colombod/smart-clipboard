import Foundation

public struct AnthropicAdapter: ImageProviderAdapter {
    public init() {}

    public func request(profile: ConnectionProfile, png: Data, key: String, format: OutputFormat, instruction: String) throws -> URLRequest {
        let model = try ProviderWire.requireModel(profile)
        // The direct API's 10 MB image limit applies after base64 encoding.
        try ProviderWire.requireImage(png, maximumBytes: 7_500_000)
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 12000,
            "system": ConversionProtocol.prompt(format: format, instruction: instruction),
            "messages": [["role": "user", "content": [
                ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]],
                ["type": "text", "text": "Convert this screenshot."]
            ]]],
            "output_config": ["format": ["type": "json_schema", "schema": ProviderWire.schema(for: format)]]
        ]
        var request = try ProviderWire.request(url: URL(string: "https://api.anthropic.com/v1/messages")!, key: key, body: body)
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        guard let size = request.httpBody?.count, size <= 32_000_000 else {
            throw ClipError.message(L10n.text("This capture and its instructions exceed Anthropic’s request limit. Try a smaller capture or shorter instructions."))
        }
        return request
    }

    public func response(_ data: Data) throws -> ProviderResponse {
        guard let body = try? ProviderWire.json(data), body["type"] as? String == "message",
              body["role"] as? String == "assistant" else {
            throw ClipError.message(L10n.text("Anthropic returned an unreadable response. Try again."))
        }
        let stop = body["stop_reason"] as? String
        if stop == "refusal" || (body["stop_details"] as? [String: Any])?["type"] as? String == "refusal" {
            throw ClipError.message(L10n.text("Anthropic declined this conversion. Try a different capture."))
        }
        guard stop == "end_turn" else {
            throw ClipError.message(L10n.text("Anthropic did not finish the conversion. Try a smaller capture."))
        }
        guard let blocks = body["content"] as? [[String: Any]] else {
            throw ClipError.message(L10n.text("Anthropic returned no conversion text. Try again."))
        }
        var parts: [String] = []
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                guard let text = block["text"] as? String else {
                    throw ClipError.message(L10n.text("Anthropic returned unreadable conversion text. Try again."))
                }
                parts.append(text)
            case "thinking", "redacted_thinking":
                continue
            default:
                // Tools are never requested; do not accept a partial answer alongside one.
                throw ClipError.message(L10n.text("Anthropic returned an unsupported response instead of a conversion. Try again."))
            }
        }
        let text = parts.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClipError.message(L10n.text("Anthropic returned no conversion text. Try again."))
        }
        return ProviderResponse(text: text, model: body["model"] as? String)
    }

    public func modelsRequest(profile: ConnectionProfile, key: String) throws -> URLRequest {
        var request = try ProviderWire.request(url: URL(string: "https://api.anthropic.com/v1/models?limit=1000")!, key: key)
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }

    public func modelsResponse(_ data: Data) throws -> [ProviderModel] {
        guard let body = try? ProviderWire.json(data), let rows = body["data"] as? [[String: Any]] else {
            throw ClipError.message(L10n.text("Could not read Anthropic’s model list. Enter a model manually."))
        }
        return rows.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            let capabilities = row["capabilities"] as? [String: Any]
            let image = capabilities?["image_input"] as? [String: Any]
            return ProviderModel(id: id, imageInput: image?["supported"] as? Bool)
        }.sorted { $0.id < $1.id }
    }
}
