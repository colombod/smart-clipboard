import AppKit
import ClipboardCore

// Refuse redirects rather than forwarding a screenshot or a key to an unselected endpoint.
final class ProviderSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct ProviderClient {
    let session: URLSession
    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 190
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: ProviderSessionDelegate(), delegateQueue: nil)
    }
    func adapter(_ provider: AIProvider) throws -> any ImageProviderAdapter {
        switch provider {
        case .openai: return OpenAIAdapter()
        case .anthropic: return AnthropicAdapter()
        case .google: return GeminiAdapter()
        case .perplexity: return PerplexityAdapter()
        case .omlx: return OMLXAdapter()
        case .codex: throw ClipError.message("ChatGPT uses the official Codex connection.")
        }
    }
    func send(_ request: URLRequest, provider: AIProvider) async throws -> Data {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ClipError.message("\(provider.title) did not return an HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            let detail: String
            switch http.statusCode {
            case 300..<400: detail = "The server redirected the request. Check the configured address."
            case 401, 403: detail = "Check the saved key and access to the selected model in Settings → Connection."
            case 404: detail = "The selected model or API address is unavailable. Check Settings → Connection."
            case 413: detail = "The image is too large. Try a smaller capture."
            case 429: detail = "The account reached a usage or rate limit. Check the provider account before retrying."
            case 500..<600: detail = "The provider is temporarily unavailable. Try again later."
            default: detail = "The provider could not process this request. Check the model and its image/structured-output support."
            }
            throw ClipError.message("\(provider.title) (HTTP \(http.statusCode)): \(detail)")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { throw ClipError.message("The provider response was too large. Try a smaller capture.") }
            data.append(byte)
            if data.count % 16_384 == 0 { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return data
    }
    func convert(png: Data, profile: ConnectionProfile, key: String, format: OutputFormat, instruction: String) async throws -> ProviderConversion {
        guard format != .image else { throw ClipError.message("Pass through does not use an AI provider.") }
        if profile.provider.requiresKey && key.isEmpty { throw ClipError.message("Save your \(profile.provider.title) API key in Settings → Connection.") }
        let adapter = try adapter(profile.provider)
        if profile.provider == .omlx {
            // oMLX can substitute a default for an unknown ID. Reject absent IDs before upload.
            let available = try adapter.modelsResponse(try await send(adapter.modelsRequest(profile: profile, key: key), provider: profile.provider))
            let selected = try ProviderWire.requireModel(profile)
            guard available.contains(where: { $0.id == selected }) else {
                throw ClipError.message("The selected oMLX model is no longer available. Choose a listed vision model in Settings → Connection.")
            }
        }
        let request = try adapter.request(profile: profile, png: png, key: key, format: format, instruction: instruction)
        let response = try adapter.response(try await send(request, provider: profile.provider))
        let result = try ConversionProtocol.decode(response.text, requested: format)
        try Task.checkCancellation()
        // oMLX echoes the requested ID, even after a server-side fallback. It is not evidence of the effective model.
        return ProviderConversion(result: result, model: profile.provider == .omlx ? nil : response.model)
    }
    func models(profile: ConnectionProfile, key: String) async throws -> [ProviderModel] {
        if profile.provider.requiresKey && key.isEmpty { throw ClipError.message("Save your \(profile.provider.title) API key in Settings → Connection.") }
        let adapter = try adapter(profile.provider)
        return try adapter.modelsResponse(try await send(adapter.modelsRequest(profile: profile, key: key), provider: profile.provider))
    }
}

extension AIService {
    static func convert(png: Data, profile: ConnectionProfile, format: OutputFormat, instruction: String, allowKeychainInteraction: Bool = false) async throws -> ProviderConversion {
        try Task.checkCancellation()
        guard let bitmap = NSBitmapImageRep(data: png), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              bitmap.pixelsWide <= 8000, bitmap.pixelsHigh <= 8000 else {
            throw ClipError.message("This image is unreadable or too large. Try a smaller capture (at most 8000 pixels per side).")
        }
        if profile.provider == .codex {
            let result = try await codex(png: png, executable: profile.executable, model: profile.model, format: format, instruction: instruction)
            return ProviderConversion(result: result)
        }
        let key = try await Task.detached { try KeyStore.read(account: profile.credentialAccount, allowInteraction: allowKeychainInteraction) }.value
        try Task.checkCancellation()
        let client = ProviderClient()
        defer { client.session.invalidateAndCancel() }
        return try await client.convert(png: png, profile: profile, key: key, format: format, instruction: instruction)
    }
    static func models(profile: ConnectionProfile, allowKeychainInteraction: Bool = false) async throws -> [ProviderModel] {
        let key = try await Task.detached { try KeyStore.read(account: profile.credentialAccount, allowInteraction: allowKeychainInteraction) }.value
        try Task.checkCancellation()
        let client = ProviderClient()
        defer { client.session.invalidateAndCancel() }
        return try await client.models(profile: profile, key: key)
    }
    @MainActor static func test(profile: ConnectionProfile) async throws -> String {
        // The unpredictable value only appears in pixels, proving image input is actually used.
        let value = String(Int.random(in: 100_000...999_999))
        let image = NSImage(size: NSSize(width: 640, height: 160))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 640, height: 160).fill()
        ("Smart Clipboard test\nCode: \(value)" as NSString).draw(at: NSPoint(x: 24, y: 36), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 32, weight: .medium), .foregroundColor: NSColor.black])
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ClipError.message("Could not create the connection test image.")
        }
        let conversion = try await convert(png: png, profile: profile, format: .text, instruction: "Extract all visible text exactly.", allowKeychainInteraction: true)
        guard conversion.result.content.contains(value) else { throw ClipError.message("The provider responded, but could not read the test image accurately. Check that the model supports images.") }
        return "Image processing verified with \(profile.provider.title)."
    }
}
