import Foundation
import Testing
@testable import ClipboardCore

struct HistoryTests {
    private func withStore(limit: Int = 50, _ test: (HistoryStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(HistoryStore(directory: directory, limit: limit), directory)
    }
    @Test func originalAndMultipleFormatsSurviveRestart() throws {
        try withStore { store, directory in
            let original = Data([1, 2, 3, 4])
            let entry = try #require(try store.add(png: original, source: "Window"))
            try store.save(SavedConversion(format: .markdown, content: "# Heading", instruction: "Retain headings"), for: entry.id)
            try store.save(SavedConversion(format: .json, content: "{\"count\":2}", instruction: "Use count"), for: entry.id)
            let reopened = try HistoryStore(directory: directory)
            #expect(try reopened.image(for: entry.id) == original)
            #expect(reopened.entries[0].conversions.map(\.format) == [.markdown, .json])
            #expect(reopened.entries[0].conversions[0].instruction == "Retain headings")
        }
    }
    @Test func oldestCapturesAndTheirFilesAreEvicted() throws {
        try withStore(limit: 2) { store, _ in
            let first = try #require(try store.add(png: Data([1]), source: "First"))
            let second = try #require(try store.add(png: Data([2]), source: "Second"))
            let third = try #require(try store.add(png: Data([3]), source: "Third"))
            #expect(store.entries.map(\.id) == [third.id, second.id])
            #expect(!FileManager.default.fileExists(atPath: store.imageURL(for: first.id).path))
            #expect(throws: (any Error).self) { try store.image(for: first.id) }
        }
    }
    @Test func loweringLimitPrunesImmediatelyAndZeroDisablesSaving() throws {
        try withStore { store, directory in
            for n in 1...3 { try store.add(png: Data([UInt8(n)]), source: "Clip") }
            try store.setLimit(1)
            #expect(store.entries.count == 1)
            try store.setLimit(0)
            #expect(try store.add(png: Data([5]), source: "Disabled") == nil)
            #expect(store.entries.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["index.json"])
        }
    }
    @Test func deletionAndClearRemoveOriginalsAndResults() throws {
        try withStore { store, directory in
            let first = try #require(try store.add(png: Data([1]), source: "First"))
            let second = try #require(try store.add(png: Data([2]), source: "Second"))
            try store.save(SavedConversion(format: .text, content: "Private text", instruction: ""), for: first.id)
            try store.remove(first.id)
            #expect(store.entries.map(\.id) == [second.id])
            #expect(!FileManager.default.fileExists(atPath: store.imageURL(for: first.id).path))
            try store.clear()
            #expect(try HistoryStore(directory: directory).entries.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: store.imageURL(for: second.id).path))
            #expect(!(try String(contentsOf: directory.appendingPathComponent("index.json"), encoding: .utf8)).contains("Private text"))
        }
    }
    @Test func regeneratingFormatReplacesOnlyThatFormatAndDoesNotReorderCaptures() throws {
        try withStore { store, _ in
            let first = try #require(try store.add(png: Data([1]), source: "First"))
            let second = try #require(try store.add(png: Data([2]), source: "Second"))
            try store.save(SavedConversion(format: .text, content: "old", instruction: ""), for: first.id)
            try store.save(SavedConversion(format: .json, content: "{}", instruction: ""), for: first.id)
            try store.save(SavedConversion(format: .text, content: "new", instruction: "translate"), for: first.id)
            #expect(store.entries.map(\.id) == [second.id, first.id])
            #expect(store.entries[1].conversions.count == 2)
            #expect(store.entries[1].conversions.last?.content == "new")
        }
    }
    @Test func corruptIndexIsPreservedAndReported() throws {
        try withStore { _, directory in
            let corrupt = Data("invalid history".utf8)
            let url = directory.appendingPathComponent("index.json")
            try corrupt.write(to: url)
            #expect(throws: (any Error).self) { try HistoryStore(directory: directory) }
            #expect(try Data(contentsOf: url) == corrupt)
        }
    }
    @Test func staleConversionCannotResurrectDeletedClip() throws {
        try withStore { store, _ in
            let entry = try #require(try store.add(png: Data([1]), source: "Clip"))
            try store.clear()
            try store.save(SavedConversion(format: .text, content: "Late result", instruction: ""), for: entry.id)
            #expect(store.entries.isEmpty)
        }
    }
    @Test func filesArePrivateToUser() throws {
        try withStore { store, directory in
            let entry = try #require(try store.add(png: Data([1]), source: "Clip"))
            #expect((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            #expect((try FileManager.default.attributesOfItem(atPath: store.imageURL(for: entry.id).path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect(store.diskBytes > 0)
        }
    }
}
