import Foundation
import Testing
@testable import ClipboardCore

struct ConversionTests {
    @Test func autoDetectsMarkdown() throws {
        let result = try ConversionProtocol.decode(##"{"format":"markdown","content":"# Meeting\n\n- Budget"}"##, requested: .auto)
        #expect(result == ConversionResult(format: .markdown, content: "# Meeting\n\n- Budget"))
    }
    @Test func explicitFormatCannotSilentlyChange() {
        #expect(throws: (any Error).self) { try ConversionProtocol.decode(#"{"format":"text","content":"hello"}"#, requested: .json) }
    }
    @Test(arguments: ["", "hello", "{}", #"{"format":"auto","content":"a"}"#, #"{"format":"image","content":"a"}"#, #"{"format":"text","content":"  "}"#])
    func malformedEnvelopeRejected(_ response: String) {
        #expect(throws: (any Error).self) { try ConversionProtocol.decode(response, requested: .auto) }
    }
    @Test func jsonMustBeValid() throws {
        #expect(throws: (any Error).self) { try ConversionProtocol.decode(#"{"format":"json","content":"{invalid}"}"#, requested: .json) }
        #expect(try ConversionProtocol.decode(#"{"format":"json","content":"{\"name\":\"Ada\",\"count\":2}"}"#, requested: .json).format == .json)
    }
    @Test func jsonScalarIsValid() throws {
        #expect(try ConversionProtocol.decode(#"{"format":"json","content":"42"}"#, requested: .json).content == "42")
    }
    @Test func fenceDoesNotChangeInnerMarkdown() throws {
        let result = try ConversionProtocol.decode("```json\n{\"format\":\"markdown\",\"content\":\"```swift\\nlet x = 1\\n```\"}\n```", requested: .markdown)
        #expect(result.content == "```swift\nlet x = 1\n```")
    }
    @Test func responseCombinesTextIgnoresReasoning() throws {
        let data = Data(#"{"status":"completed","output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"hello "},{"type":"output_text","text":"world"}]}]}"#.utf8)
        #expect(try ConversionProtocol.responseText(data) == "hello world")
    }
    @Test func truncatedResponseRejected() {
        let data = Data(#"{"status":"incomplete","output":[{"content":[{"type":"output_text","text":"partial"}]}]}"#.utf8)
        #expect(throws: (any Error).self) { try ConversionProtocol.responseText(data) }
    }
    @Test func refusalAndMissingOutputReported() {
        #expect(throws: (any Error).self) { try ConversionProtocol.responseText(Data(#"{"status":"completed","output":[{"content":[{"type":"refusal","refusal":"Cannot convert"}]}]}"#.utf8)) }
        #expect(throws: (any Error).self) { try ConversionProtocol.responseText(Data(#"{"status":"completed","output":[]}"#.utf8)) }
    }
    @Test func payloadHasImageSchemaAndNoTools() throws {
        let data = try ConversionProtocol.requestBody(png: Data([1,2,3]), model: "vision-test", format: .yaml, instruction: "Translate to Italian")
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect(body["model"] as? String == "vision-test")
        #expect(body["tools"] == nil)
        let messages = try #require(body["input"] as? [[String: Any]])
        #expect(messages.count == 2)
        let image = try #require((messages[1]["content"] as? [[String: Any]])?.first)
        #expect(image["image_url"] as? String == "data:image/png;base64,AQID")
        let developer = try #require((messages[0]["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(developer.contains("Translate to Italian"))
        #expect(developer.contains("untrusted data"))
        let text = try #require(body["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["strict"] as? Bool == true)
    }
    @Test func exportExtensions() {
        #expect(OutputFormat.markdown.fileExtension == "md")
        #expect(OutputFormat.image.fileExtension == "png")
        #expect(OutputFormat.description.fileExtension == "txt")
        #expect(OutputFormat.svg.fileExtension == "svg")
    }
}
