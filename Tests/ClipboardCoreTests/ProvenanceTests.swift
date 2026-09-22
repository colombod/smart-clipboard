import Foundation
import Testing
@testable import ClipboardCore

struct ProvenanceTests {
    @Test func legacyHistoryWithoutProvenanceCanBeLoadedAndSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProvenanceTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let legacy: [[String: Any]] = [[
            "id": id.uuidString, "createdAt": 0, "source": "Legacy capture",
            "conversions": [["format": "text", "content": "Earlier output", "instruction": "Keep names", "createdAt": 0]]
        ]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: directory.appendingPathComponent("index.json"))
        let original = Data([1, 2, 3])
        try original.write(to: directory.appendingPathComponent(id.uuidString + ".png"))
        let store = try HistoryStore(directory: directory)
        var conversion = try #require(store.entries.first?.conversions.first)
        #expect(conversion.provenance == nil)
        #expect(conversion.content == "Earlier output")
        #expect(try store.image(for: id) == original)
        conversion.content = "Edited legacy output"
        try store.save(conversion, for: id)
        let reopened = try HistoryStore(directory: directory)
        #expect(reopened.entries.first?.conversions.first?.content == "Edited legacy output")
        #expect(reopened.entries.first?.conversions.first?.provenance == nil)
    }
}
