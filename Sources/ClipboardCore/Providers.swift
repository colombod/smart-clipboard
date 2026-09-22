import Foundation
import CryptoKit

public enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openai, codex, anthropic, google, perplexity, omlx
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .codex: return "ChatGPT via Codex"
        case .anthropic: return "Anthropic"
        case .google: return "Google Gemini"
        case .perplexity: return "Perplexity"
        case .omlx: return "Local / oMLX"
        }
    }
    public var requiresKey: Bool { self != .codex && self != .omlx }
}

public struct ConnectionProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: AIProvider
    public var model: String
    public var endpoint: String
    public var executable: String
    public init(id: String? = nil, provider: AIProvider, model: String = "", endpoint: String = "", executable: String = "") {
        self.id = id ?? provider.rawValue
        self.provider = provider
        self.model = model
        self.endpoint = endpoint.isEmpty && provider == .omlx ? "http://127.0.0.1:8000/v1" : endpoint
        self.executable = executable
    }
    // Keep the existing OpenAI item in place; migrating settings never reads or moves a secret.
    public var credentialAccount: String {
        if id == "openai" && provider == .openai { return "openai-api-key" }
        let account = "connection-\(id)-\(provider.rawValue)"
        guard provider == .omlx else { return account }
        // A changed local-server address must never receive another server's saved key.
        let canonical = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fingerprint = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return account + "-" + fingerprint
    }
}

public struct ProviderModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let imageInput: Bool?
    public init(id: String, imageInput: Bool? = nil) { self.id = id; self.imageInput = imageInput }
}

public struct ProviderResponse: Equatable, Sendable {
    public let text: String
    public let model: String?
    public init(text: String, model: String? = nil) { self.text = text; self.model = model }
}

public struct ProviderConversion: Equatable, Sendable {
    public let result: ConversionResult
    public let model: String?
    public init(result: ConversionResult, model: String? = nil) { self.result = result; self.model = model }
}

public protocol ImageProviderAdapter: Sendable {
    func request(profile: ConnectionProfile, png: Data, key: String, format: OutputFormat, instruction: String) throws -> URLRequest
    func response(_ data: Data) throws -> ProviderResponse
    func modelsRequest(profile: ConnectionProfile, key: String) throws -> URLRequest
    func modelsResponse(_ data: Data) throws -> [ProviderModel]
}

public enum ProviderWire {
    public static func schema(for format: OutputFormat) -> [String: Any] {
        let allowed = OutputFormat.allCases.filter { $0 != .auto && $0 != .image && (format == .auto || $0 == format) }
        return ["type": "object", "additionalProperties": false,
         "properties": ["format": ["type": "string", "enum": allowed.map(\.rawValue)],
                        "content": ["type": "string"]], "required": ["format", "content"]]
    }
    public static func json(_ data: Data) throws -> [String: Any] {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClipError.message("The provider returned an unreadable response.")
        }
        return body
    }
    public static func request(url: URL, key: String, body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }
    public static func requireModel(_ profile: ConnectionProfile) throws -> String {
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw ClipError.message("Choose an image-capable model in Settings → Connection.") }
        return model
    }
    public static func requireImage(_ png: Data, maximumBytes: Int) throws {
        guard !png.isEmpty, png.count <= maximumBytes else {
            throw ClipError.message("This image exceeds the selected provider’s limit. Try a smaller capture.")
        }
    }
    public static func listedModels(_ data: Data) throws -> [ProviderModel] {
        let body = try json(data)
        guard let rows = body["data"] as? [[String: Any]] else { throw ClipError.message("Could not read the provider’s model list. Enter a model manually.") }
        return rows.compactMap { row in (row["id"] as? String).map { ProviderModel(id: $0) } }.sorted { $0.id < $1.id }
    }
}
