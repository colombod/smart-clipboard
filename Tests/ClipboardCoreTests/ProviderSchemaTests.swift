import Foundation
import Testing
@testable import ClipboardCore

struct ProviderSchemaTests {
    private let editableFormats: Set<String> = ["description", "text", "markdown", "html", "svg", "json", "yaml"]

    @Test(arguments: [OutputFormat.description, .text, .markdown, .html, .svg, .json, .yaml, .auto])
    func everyNativeRequestConstrainsTheSelectedFormat(_ requested: OutputFormat) throws {
        let routes: [(AIProvider, any ImageProviderAdapter, [String])] = [
            (.openai, OpenAIAdapter(), ["text", "format", "schema"]),
            (.anthropic, AnthropicAdapter(), ["output_config", "format", "schema"]),
            (.google, GeminiAdapter(), ["response_format", "schema"]),
            (.perplexity, PerplexityAdapter(), ["response_format", "json_schema", "schema"]),
            (.omlx, OMLXAdapter(), ["structured_outputs", "json"])
        ]
        for (provider, adapter, path) in routes {
            let request = try adapter.request(profile: ConnectionProfile(provider: provider, model: "vision-fixture"),
                                              png: Data([1, 2, 3]), key: "fixture-key", format: requested, instruction: "")
            var schema = try ProviderWire.json(#require(request.httpBody))
            for key in path { schema = try #require(schema[key] as? [String: Any]) }
            let properties = try #require(schema["properties"] as? [String: Any])
            let format = try #require(properties["format"] as? [String: Any])
            let allowed = try #require(format["enum"] as? [String])
            let expected = requested == .auto ? editableFormats : [requested.rawValue]
            #expect(Set(allowed) == expected, "\(provider.rawValue) permits the wrong format for \(requested.rawValue).")
            #expect(allowed.count == expected.count)
            #expect(schema["additionalProperties"] as? Bool == false)
            #expect(Set(schema["required"] as? [String] ?? []) == ["format", "content"])
        }
    }

    @Test func sharedNativeSchemaKeepsAutoFlexibleAndDescriptionExact() throws {
        for (requested, expected) in [(OutputFormat.description, Set(["description"])), (.auto, editableFormats)] {
            let data = try JSONSerialization.data(withJSONObject: ProviderWire.schema(for: requested))
            let schema = try ProviderWire.json(data)
            let properties = try #require(schema["properties"] as? [String: Any])
            let format = try #require(properties["format"] as? [String: Any])
            #expect(Set(format["enum"] as? [String] ?? []) == expected)
            #expect(Set(properties.keys) == ["format", "content"])
            #expect((properties["content"] as? [String: Any])?["type"] as? String == "string")
        }
    }

    @Test func modelChoosingMarkdownForDescriptionStillFailsValidation() {
        let output = ##"{"format":"markdown","content":"# Visible inventory"}"##
        #expect(throws: (any Error).self) { try ConversionProtocol.decode(output, requested: .description) }
    }

    @Test func plainTextPromptUsesTabsInsteadOfMarkdownTables() {
        let prompt = ConversionProtocol.prompt(format: .text, instruction: "Preserve the source language")
        #expect(prompt.contains("Do not paraphrase or introduce Markdown formatting or table syntax"))
        #expect(prompt.contains("including any visible Markdown syntax"))
        #expect(prompt.contains("Use tabs and line breaks to represent drawn table columns and rows"))
        #expect(prompt.contains("The format must be text"))
        #expect(prompt.contains("Preserve the source language"))
    }

    @Test(arguments: [OutputFormat.json, .yaml, .auto])
    func structuredContentPromptForbidsRepeatingTheTransportEnvelope(_ requested: OutputFormat) {
        let prompt = ConversionProtocol.prompt(format: requested, instruction: "")
        #expect(prompt.contains("Do not repeat the transport envelope inside content"))
        #expect(prompt.contains("the extracted document, not another conversion object with format and content fields"))
        #expect(prompt.contains("Return ONLY a JSON object with exactly two string fields"))
    }
}
