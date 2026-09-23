import Foundation

public struct GeminiAdapter: ImageProviderAdapter {
    public init() {}

    public func request(profile: ConnectionProfile, png: Data, key: String, format: OutputFormat, instruction: String) throws -> URLRequest {
        let model = Self.modelID(try ProviderWire.requireModel(profile))
        guard !model.isEmpty else {
            throw ClipError.message(L10n.text("Choose an image-capable model in Settings → Connection."))
        }
        // Base64 expands the image by a third; the serialized request is checked below.
        try ProviderWire.requireImage(png, maximumBytes: 15_000_000)
        let body: [String: Any] = [
            "model": model,
            "store": false,
            "system_instruction": ConversionProtocol.prompt(format: format, instruction: instruction),
            "input": [
                ["type": "image", "mime_type": "image/png", "data": png.base64EncodedString()],
                ["type": "text", "text": "Convert this screenshot."]
            ],
            "generation_config": ["max_output_tokens": 12000],
            "response_format": ["type": "text", "mime_type": "application/json", "schema": ProviderWire.schema(for: format)]
        ]
        var request = try ProviderWire.request(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!, key: "", body: body)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        guard let size = request.httpBody?.count, size <= 20_000_000 else {
            throw ClipError.message(L10n.text("This capture and its instructions exceed Gemini’s request limit. Try a smaller capture or shorter instructions."))
        }
        return request
    }

    public func response(_ data: Data) throws -> ProviderResponse {
        guard let body = try? ProviderWire.json(data) else {
            throw ClipError.message(L10n.text("Gemini returned an unreadable response. Try again."))
        }
        if let error = body["error"], !(error is NSNull) {
            throw ClipError.message(L10n.text("Gemini could not complete this conversion. Check your connection settings or try a different capture."))
        }
        guard body["status"] as? String == "completed" else {
            throw ClipError.message(L10n.text("Gemini did not finish the conversion. Try a smaller capture."))
        }
        guard let steps = body["steps"] as? [[String: Any]] else {
            throw ClipError.message(L10n.text("Gemini returned no conversion text. Try again."))
        }
        var parts: [String] = []
        for step in steps {
            switch step["type"] as? String {
            case "thought":
                continue
            case "model_output":
                guard let blocks = step["content"] as? [[String: Any]] else {
                    throw ClipError.message(L10n.text("Gemini returned unreadable conversion text. Try again."))
                }
                for block in blocks {
                    guard block["type"] as? String == "text", let text = block["text"] as? String else {
                        throw ClipError.message(L10n.text("Gemini returned an unsupported response instead of a conversion. Try again."))
                    }
                    parts.append(text)
                }
            default:
                // Reject tool calls, results and other steps; conversion never enables tools.
                throw ClipError.message(L10n.text("Gemini returned an unsupported response instead of a conversion. Try again."))
            }
        }
        let text = parts.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClipError.message(L10n.text("Gemini returned no conversion text. Try again."))
        }
        return ProviderResponse(text: text, model: body["model"] as? String)
    }

    public func modelsRequest(profile: ConnectionProfile, key: String) throws -> URLRequest {
        var request = try ProviderWire.request(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")!, key: "")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        return request
    }

    public func modelsResponse(_ data: Data) throws -> [ProviderModel] {
        guard let body = try? ProviderWire.json(data), let rows = body["models"] as? [[String: Any]] else {
            throw ClipError.message(L10n.text("Could not read Gemini’s model list. Enter a model manually."))
        }
        return rows.compactMap { row in
            guard let name = row["name"] as? String else { return nil }
            let id = Self.modelID(name)
            guard !id.isEmpty else { return nil }
            // Generation-method support is not evidence of image input support.
            return ProviderModel(id: id)
        }.sorted { $0.id < $1.id }
    }

    private static func modelID(_ name: String) -> String {
        name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
    }
}
