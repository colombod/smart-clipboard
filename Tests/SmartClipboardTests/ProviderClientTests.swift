import Foundation
import Testing
import ClipboardCore
@testable import SmartClipboard

private final class ProviderHTTPFixture: URLProtocol, @unchecked Sendable {
    static var responseStatus = 200
    static var responseBody = Data()
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseStatus, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct ProviderClientTests {
    private func client(status: Int, body: String) -> ProviderClient {
        ProviderHTTPFixture.requests = []
        ProviderHTTPFixture.responseStatus = status
        ProviderHTTPFixture.responseBody = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderHTTPFixture.self]
        return ProviderClient(session: URLSession(configuration: configuration))
    }

    @Test func nativeRequestReturnsValidatedConversionAndModel() async throws {
        let client = client(status: 200, body: #"{"status":"completed","model":"actual-model","output":[{"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"{\"format\":\"text\",\"content\":\"fixture 752\"}"}]}]}"#)
        defer { client.session.invalidateAndCancel() }
        let converted = try await client.convert(png: Data([1]), profile: ConnectionProfile(provider: .openai, model: "selected-model"), key: "fixture-key", format: .text, instruction: "")
        #expect(converted.result.content == "fixture 752")
        #expect(converted.model == "actual-model")
        #expect(ProviderHTTPFixture.requests.count == 1)
        #expect(ProviderHTTPFixture.requests.first?.url?.host == "api.openai.com")
        #expect(ProviderHTTPFixture.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
    }

    @Test func authenticationFailureDoesNotLeakBodyOrRetryAnotherProvider() async {
        let client = client(status: 401, body: #"{"error":{"message":"private screenshot text and fixture-key"}}"#)
        defer { client.session.invalidateAndCancel() }
        do {
            _ = try await client.convert(png: Data([1]), profile: ConnectionProfile(provider: .openai, model: "selected-model"), key: "fixture-key", format: .text, instruction: "")
            Issue.record("Expected authentication failure")
        } catch {
            #expect(!error.localizedDescription.contains("private screenshot"))
            #expect(!error.localizedDescription.contains("fixture-key"))
            #expect(error.localizedDescription.contains("401"))
        }
        #expect(ProviderHTTPFixture.requests.count == 1)
    }

    @Test func successfulHTTPDoesNotAcceptWrongFormat() async {
        let client = client(status: 200, body: #"{"status":"completed","output":[{"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"{\"format\":\"text\",\"content\":\"not JSON\"}"}]}]}"#)
        defer { client.session.invalidateAndCancel() }
        await #expect(throws: (any Error).self) {
            try await client.convert(png: Data([1]), profile: ConnectionProfile(provider: .openai, model: "selected-model"), key: "fixture-key", format: .json, instruction: "")
        }
        #expect(ProviderHTTPFixture.requests.count == 1)
    }

    @Test func missingCredentialsAndPassThroughNeverReachTransport() async {
        let client = client(status: 200, body: "{}")
        defer { client.session.invalidateAndCancel() }
        for (format, key) in [(OutputFormat.text, ""), (.image, "fixture-key")] {
            await #expect(throws: (any Error).self) {
                try await client.convert(png: Data([1]), profile: ConnectionProfile(provider: .openai, model: "selected-model"), key: key, format: format, instruction: "")
            }
        }
        #expect(ProviderHTTPFixture.requests.isEmpty)
    }

    @Test func missingLocalModelNeverUploadsScreenshot() async {
        let client = client(status: 200, body: #"{"data":[{"id":"different-model"}]}"#)
        defer { client.session.invalidateAndCancel() }
        await #expect(throws: (any Error).self) {
            try await client.convert(png: Data([1]), profile: ConnectionProfile(provider: .omlx, model: "missing-model"), key: "", format: .text, instruction: "")
        }
        #expect(ProviderHTTPFixture.requests.count == 1)
        #expect(ProviderHTTPFixture.requests.first?.httpMethod == "GET")
        #expect(ProviderHTTPFixture.requests.first?.url?.path == "/v1/models")
    }

    @Test func oversizedResponseIsStoppedBeforeDecoding() async {
        let client = client(status: 200, body: String(repeating: "x", count: 2_000_001))
        defer { client.session.invalidateAndCancel() }
        do {
            _ = try await client.convert(png: Data([1]), profile: ConnectionProfile(provider: .openai, model: "selected-model"), key: "fixture-key", format: .text, instruction: "")
            Issue.record("Expected response size failure")
        } catch {
            #expect(error.localizedDescription.contains("response was too large"))
        }
        #expect(ProviderHTTPFixture.requests.count == 1)
    }
}
