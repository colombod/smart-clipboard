import Foundation

public struct OpenAIAdapter: ImageProviderAdapter {
    public init() {}
    public func request(profile: ConnectionProfile, png: Data, key: String, format: OutputFormat, instruction: String) throws -> URLRequest {
        let model = try ProviderWire.requireModel(profile)
        try ProviderWire.requireImage(png, maximumBytes: 20_000_000)
        var request = try ProviderWire.request(url: URL(string: "https://api.openai.com/v1/responses")!, key: key)
        request.httpMethod = "POST"
        request.httpBody = try ConversionProtocol.requestBody(png: png, model: model, format: format, instruction: instruction)
        return request
    }
    public func response(_ data: Data) throws -> ProviderResponse {
        let body = try ProviderWire.json(data)
        return ProviderResponse(text: try ConversionProtocol.responseText(data), model: body["model"] as? String)
    }
    public func modelsRequest(profile: ConnectionProfile, key: String) throws -> URLRequest {
        try ProviderWire.request(url: URL(string: "https://api.openai.com/v1/models")!, key: key)
    }
    public func modelsResponse(_ data: Data) throws -> [ProviderModel] { try ProviderWire.listedModels(data) }
}
