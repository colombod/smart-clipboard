import Foundation
import Testing
@testable import ClipboardCore

struct TracingHistoryTests {
    private func withStore(_ body: (HistoryStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(HistoryStore(directory: directory), directory)
    }
    private var large: String { String(repeating: "<path d='M0 0L1 1'/>\n", count: 5000) }

    @Test func methodsAndTraceSettingsKeepSeparateVariants() throws {
        try withStore { store, directory in
            let entry = try #require(try store.add(png: Data([1]), source: "Capture"))
            try store.save(SavedConversion(format: .svg, content: "AI", instruction: ""), for: entry.id)
            for preset in TracePreset.allCases {
                for detail in TraceDetail.allCases {
                    let settings = TraceSettings(preset: preset, detail: detail)
                    try store.save(SavedConversion(format: .svg, content: settings.variantID, instruction: "", method: .vtracer, traceSettings: settings), for: entry.id)
                }
            }
            try store.save(SavedConversion(format: .text, content: "AI text", instruction: "", method: .ai), for: entry.id)
            try store.save(SavedConversion(format: .text, content: "Local text", instruction: "", method: .appleVision), for: entry.id)
            try store.save(SavedConversion(format: .svg, content: "Updated", instruction: "", method: .vtracer), for: entry.id)
            let reopened = try HistoryStore(directory: directory)
            let results = try #require(reopened.entries.first?.conversions)
            #expect(results.count == 9)
            #expect(Set(results.map(\.id)).count == 9)
            #expect(results.last?.content == "Updated")
            #expect(results.last?.matches(format: .svg, method: .vtracer, traceSettings: TraceSettings()) == true)
            #expect(TraceSettings().variantID == "photo:balanced")
            #expect(TracePreset.lineArt.rawValue == "line-art")
        }
    }
    @Test func legacyMethodUsesOnlyKnownProvenance() throws {
        for (provider, expected) in [("apple-vision", ConversionMethod.appleVision), ("omlx", .ai), ("", .ai)] {
            var object: [String: Any] = ["format": "text", "content": "Legacy", "instruction": "", "createdAt": 0]
            if !provider.isEmpty { object["provenance"] = ["providerID": provider, "requestedModel": "", "userEdited": false] }
            let result = try JSONDecoder().decode(SavedConversion.self, from: JSONSerialization.data(withJSONObject: object))
            #expect(result.method == expected)
            #expect(result.outputLanguage == nil)
        }
    }
    @Test func largeResultIsLazyPrivateAndSurvivesRestart() throws {
        try withStore { store, directory in
            let entry = try #require(try store.add(png: Data([1]), source: "Region"))
            try store.save(SavedConversion(format: .svg, content: large, instruction: "", method: .vtracer), for: entry.id)
            let result = try #require(store.entries.first?.conversions.first)
            #expect(result.content.isEmpty)
            #expect(result.contentIsExternal)
            #expect(result.contentByteCount == large.utf8.count)
            #expect(result.preview.count <= 240)
            #expect(store.entries.first?.title == "Region")
            let artifact = directory.appendingPathComponent(try #require(result.contentArtifact))
            #expect((try FileManager.default.attributesOfItem(atPath: artifact.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect(try Data(contentsOf: directory.appendingPathComponent("index.json")).count < 3000)
            let reopened = try HistoryStore(directory: directory)
            #expect(try reopened.content(for: result, in: entry.id) == large)
            #expect(reopened.entries[0].conversions[0].content.isEmpty)
            try reopened.add(png: Data([2]), source: "Another capture")
            #expect(reopened.entries[1].conversions[0].contentArtifact == result.contentArtifact)
        }
    }
    @Test func existingLargeInlineHistoryMigratesWithoutChangingOutput() throws {
        try withStore { store, directory in
            let entry = try #require(try store.add(png: Data([1]), source: "Legacy"))
            let conversion = SavedConversion(format: .svg, content: large, instruction: "")
            let legacy = HistoryEntry(id: entry.id, createdAt: entry.createdAt, source: entry.source, conversions: [conversion])
            try JSONEncoder().encode([legacy]).write(to: directory.appendingPathComponent("index.json"))
            let migrated = try HistoryStore(directory: directory)
            let result = try #require(migrated.entries.first?.conversions.first)
            #expect(result.method == .ai)
            #expect(result.contentIsExternal)
            #expect(try migrated.content(for: result, in: entry.id) == large)
        }
    }
    @Test func oversizedLegacyTextSurvivesWhileNewOversizedSavesAreRejected() throws {
        try withStore { store, directory in
            let oversized = String(repeating: "x", count: HistoryStore.maximumContentBytes + 1)
            let original = try #require(try store.add(png: Data([1]), source: "Legacy large capture"))
            let normal = try #require(try store.add(png: Data([2]), source: "Normal capture"))
            let legacy: [[String: Any]] = [
                ["id": original.id.uuidString, "createdAt": 0, "source": original.source,
                 "conversions": [["format": "text", "content": oversized, "instruction": "", "createdAt": 0]]],
                ["id": normal.id.uuidString, "createdAt": 0, "source": normal.source,
                 "conversions": [["format": "text", "content": "Normal saved result", "instruction": "", "createdAt": 0]]]
            ]
            let index = directory.appendingPathComponent("index.json")
            try JSONSerialization.data(withJSONObject: legacy).write(to: index)
            let migrated = try HistoryStore(directory: directory)
            let oldResult = try #require(migrated.entries.first?.conversions.first)
            #expect(!oldResult.contentIsExternal)
            #expect(try migrated.content(for: oldResult, in: original.id) == oversized)
            // Ordinary updates must remain available alongside the legacy value.
            try migrated.save(SavedConversion(format: .markdown, content: "**Still usable**", instruction: ""), for: normal.id)
            let beforeRejectedSave = try Data(contentsOf: index)
            #expect(throws: (any Error).self) {
                try migrated.save(SavedConversion(format: .text, content: oversized, instruction: ""), for: normal.id)
            }
            #expect(try Data(contentsOf: index) == beforeRejectedSave)
            let reopened = try HistoryStore(directory: directory)
            #expect(reopened.entries.count == 2)
            #expect(try reopened.image(for: original.id) == Data([1]))
            #expect(try reopened.image(for: normal.id) == Data([2]))
            #expect(try reopened.content(for: oldResult, in: original.id) == oversized)
            let normalResults = try #require(reopened.entries.first(where: { $0.id == normal.id })?.conversions)
            #expect(normalResults.map(\.content) == ["Normal saved result", "**Still usable**"])
        }
    }
    @Test func replacementAndRetentionRemoveOnlyUnreferencedArtifacts() throws {
        try withStore { store, directory in
            let first = try #require(try store.add(png: Data([1]), source: "First"))
            try store.save(SavedConversion(format: .svg, content: large, instruction: "", method: .vtracer), for: first.id)
            let old = try #require(store.entries[0].conversions[0].contentArtifact)
            try store.save(SavedConversion(format: .svg, content: large + "new", instruction: "", method: .vtracer), for: first.id)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(old).path))
            let retained = try #require(store.entries[0].conversions[0].contentArtifact)
            let second = try #require(try store.add(png: Data([2]), source: "Second"))
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(retained).path))
            try store.setLimit(1)
            #expect(store.entries.map(\.id) == [second.id])
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(retained).path))
            try store.clear()
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["index.json"])
        }
    }
    @Test func editedExternalConversionGetsNewContent() throws {
        try withStore { store, _ in
            let entry = try #require(try store.add(png: Data([1]), source: "Capture"))
            try store.save(SavedConversion(format: .svg, content: large, instruction: "", method: .vtracer), for: entry.id)
            var result = store.entries[0].conversions[0]
            result.content = "Edited"
            #expect(!result.contentIsExternal)
            try store.save(result, for: entry.id)
            #expect(try store.content(for: result, in: entry.id) == "Edited")
        }
    }
    @Test func damagedOrMissingArtifactsDoNotEraseHistory() throws {
        try withStore { store, directory in
            let entry = try #require(try store.add(png: Data([1]), source: "Capture"))
            try store.save(SavedConversion(format: .svg, content: large, instruction: "", method: .vtracer), for: entry.id)
            let result = store.entries[0].conversions[0]
            let artifact = directory.appendingPathComponent(try #require(result.contentArtifact))
            try Data(repeating: 65, count: result.contentByteCount).write(to: artifact)
            let reopened = try HistoryStore(directory: directory)
            #expect(throws: (any Error).self) { try reopened.content(for: result, in: entry.id) }
            #expect(reopened.entries.count == 1)
            #expect(try reopened.image(for: entry.id) == Data([1]))
            try FileManager.default.removeItem(at: artifact)
            #expect(throws: (any Error).self) { try reopened.content(for: result, in: entry.id) }
        }
    }
    @Test func artifactSymlinksCannotReadOutsideHistory() throws {
        try withStore { store, directory in
            let entry = try #require(try store.add(png: Data([1]), source: "Capture"))
            try store.save(SavedConversion(format: .svg, content: large, instruction: ""), for: entry.id)
            let result = store.entries[0].conversions[0]
            let artifact = directory.appendingPathComponent(try #require(result.contentArtifact))
            let outside = directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: outside) }
            try Data(large.utf8).write(to: outside)
            try FileManager.default.removeItem(at: artifact)
            try FileManager.default.createSymbolicLink(at: artifact, withDestinationURL: outside)
            #expect(throws: (any Error).self) { try store.content(for: result, in: entry.id) }
            try store.clear()
            #expect(FileManager.default.fileExists(atPath: outside.path))
        }
    }
    @Test func escapingReferenceRejectsIndexWithoutOverwritingIt() throws {
        try withStore { store, directory in
            let entry = try #require(try store.add(png: Data([1]), source: "Capture"))
            try store.save(SavedConversion(format: .svg, content: large, instruction: ""), for: entry.id)
            let index = directory.appendingPathComponent("index.json")
            var objects = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [[String: Any]])
            var conversions = try #require(objects[0]["conversions"] as? [[String: Any]])
            conversions[0]["contentArtifact"] = "../outside.txt"
            objects[0]["conversions"] = conversions
            let bad = try JSONSerialization.data(withJSONObject: objects)
            try bad.write(to: index)
            #expect(throws: (any Error).self) { try HistoryStore(directory: directory) }
            #expect(try Data(contentsOf: index) == bad)
        }
    }
    @Test func failedIndexCommitKeepsOldResultAndCleansNewArtifact() throws {
        try withStore { store, directory in
            let entry = try #require(try store.add(png: Data([1]), source: "Capture"))
            try store.save(SavedConversion(format: .svg, content: large, instruction: ""), for: entry.id)
            let result = store.entries[0].conversions[0]
            let index = directory.appendingPathComponent("index.json")
            try FileManager.default.removeItem(at: index)
            try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) { try store.save(SavedConversion(format: .svg, content: large + "changed", instruction: ""), for: entry.id) }
            #expect(store.entries[0].conversions[0] == result)
            #expect(try store.content(for: result, in: entry.id) == large)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("result-") }.count == 1)
        }
    }
}
