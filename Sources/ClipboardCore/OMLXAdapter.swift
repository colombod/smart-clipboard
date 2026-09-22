import Foundation

public struct OMLXAdapter: ImageProviderAdapter {
    public init() {}

    public func request(profile: ConnectionProfile, png: Data, key: String, format: OutputFormat, instruction: String) throws -> URLRequest {
        try ProviderWire.requireImage(png, maximumBytes: 20 * 1024 * 1024)
        let model = try ProviderWire.requireModel(profile)
        let url = try endpoint(profile, route: "chat/completions", key: key)
        // Unlike response_format, structured_outputs fails if grammar enforcement is unavailable.
        return try ProviderWire.request(url: url, key: key, body: [
            "model": model,
            "stream": false,
            "max_tokens": 12000,
            "tools": [],
            "tool_choice": "none",
            "structured_outputs": ["json": ProviderWire.schema],
            "messages": [
                ["role": "system", "content": ConversionProtocol.prompt(format: format, instruction: instruction)],
                ["role": "user", "content": [
                    ["type": "text", "text": "Convert this screenshot using the requested format."],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64," + png.base64EncodedString()]]
                ]]
            ]
        ])
    }

    public func response(_ data: Data) throws -> ProviderResponse {
        let body = try LocalPerplexityResponse.object(data)
        guard let choices = body["choices"] as? [[String: Any]], choices.count == 1,
              let choice = choices.first, choice["finish_reason"] as? String == "stop",
              let message = choice["message"] as? [String: Any],
              message["role"] as? String == "assistant" else {
            throw ClipError.message("oMLX did not finish the conversion. Try a smaller capture or another image-capable local model.")
        }
        guard !LocalPerplexityResponse.present(message["function_call"]),
              !LocalPerplexityResponse.present(message["refusal"]),
              LocalPerplexityResponse.emptyArray(message["tool_calls"]),
              let text = message["content"] as? String else {
            throw ClipError.message("oMLX returned a tool request or no usable conversion. The clipboard was not changed.")
        }
        try LocalPerplexityResponse.validateEnvelope(text)
        return ProviderResponse(text: text, model: body["model"] as? String)
    }

    public func modelsRequest(profile: ConnectionProfile, key: String) throws -> URLRequest {
        try ProviderWire.request(url: endpoint(profile, route: "models", key: key), key: key)
    }

    public func modelsResponse(_ data: Data) throws -> [ProviderModel] {
        // oMLX's public model list does not advertise vision capability.
        try ProviderWire.listedModels(data)
    }

    private func endpoint(_ profile: ConnectionProfile, route: String, key: String) throws -> URL {
        let value = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, var parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let rawHost = parts.host, !rawHost.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port == nil || (1...65535).contains(parts.port!) else {
            throw ClipError.message("Enter an oMLX server URL without a username, password, query, or fragment.")
        }
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let loopback = isLoopback(host)
        guard scheme == "https" || loopback || isPrivateLAN(host) else {
            throw ClipError.message("Use HTTPS for a remote oMLX server. HTTP is supported only for this Mac or a private LAN address.")
        }
        guard loopback || !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClipError.message("Enter the server API key before connecting to oMLX on another computer.")
        }
        // Keep the API prefix explicit so a full completion URL is never appended twice.
        let path = parts.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.isEmpty || path == "v1" else {
            throw ClipError.message("The oMLX server URL should end in /v1, for example http://127.0.0.1:8000/v1.")
        }
        parts.path = "/v1/" + route
        guard let url = parts.url else { throw ClipError.message("The oMLX server URL is invalid.") }
        return url
    }

    private func isLoopback(_ host: String) -> Bool {
        if host == "localhost" || host == "localhost." || host == "::1" { return true }
        return ipv4(host)?.first == 127
    }

    private func isPrivateLAN(_ host: String) -> Bool {
        if host.hasSuffix(".local") || host.hasSuffix(".local.") { return true }
        if let octets = ipv4(host) {
            return octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1])) ||
                (octets[0] == 192 && octets[1] == 168) || (octets[0] == 169 && octets[1] == 254)
        }
        if host.contains(":"), let first = host.split(separator: ":").first, let prefix = UInt16(first, radix: 16) {
            return prefix & 0xfe00 == 0xfc00 || prefix & 0xffc0 == 0xfe80
        }
        return false
    }

    private func ipv4(_ host: String) -> [Int]? {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return nil }
        let octets = pieces.compactMap { piece -> Int? in
            guard let number = Int(piece), String(number) == piece, (0...255).contains(number) else { return nil }
            return number
        }
        return octets.count == 4 ? octets : nil
    }
}

// Both adapters return a bounded extraction envelope; the caller also checks the requested format.
enum LocalPerplexityResponse {
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 2 * 1024 * 1024 else { throw ClipError.message("The provider response was too large. Try a smaller capture.") }
        let body = try ProviderWire.json(data)
        guard !present(body["error"]) else { throw ClipError.message("The provider could not complete the conversion. Check the connection and selected model.") }
        return body
    }

    static func present(_ value: Any?) -> Bool { value != nil && !(value is NSNull) }

    static func emptyArray(_ value: Any?) -> Bool {
        guard present(value) else { return true }
        return (value as? [Any])?.isEmpty == true
    }

    static func validateEnvelope(_ text: String) throws {
        guard let data = text.data(using: .utf8), data.count <= 1024 * 1024,
              let object = try? ProviderWire.json(data), Set(object.keys) == ["format", "content"],
              object["format"] is String, object["content"] is String else {
            throw ClipError.message("The model returned an invalid conversion. Choose a model that supports image input and structured output.")
        }
        _ = try ConversionProtocol.decode(text, requested: .auto)
    }
}
