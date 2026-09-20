import Foundation
import AppKit
import Testing
import ClipboardCore
@testable import SmartClipboard

@MainActor struct HistoryModelTests {
    private func withModel(_ test: (AppModel, UserDefaults, URL) throws -> Void) throws {
        let name = "SmartClipboardTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false)
        try test(model, defaults, directory)
    }
    @Test func reopeningUsesOriginalAndPreservesSeveralOutputs() throws {
        try withModel { model, defaults, directory in
            let original = Data([1, 2, 3])
            model.acceptCapture(original, source: "Original")
            model.resultFormat = .markdown; model.output = "# Title"; model.persistCurrentOutput()
            model.resultFormat = .json; model.output = "{}"; model.persistCurrentOutput()
            model.clear()
            let entry = try #require(model.history.first)
            model.openHistory(entry, showWindow: false)
            #expect(model.png == original)
            #expect(model.savedConversions.count == 2)
            model.useSavedConversion(try #require(model.savedConversions.first))
            #expect(model.output == "# Title")
            #expect(model.format == .markdown)
            let reopened = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false)
            #expect(reopened.history.count == 1)
        }
    }
    @Test func deletingActiveCaptureClearsWorkingCopy() throws {
        try withModel { model, _, _ in
            model.acceptCapture(Data([1]), source: "Clip")
            model.output = "Saved output"; model.persistCurrentOutput()
            model.deleteHistory(try #require(model.history.first))
            #expect(model.png == nil)
            #expect(model.output.isEmpty)
            #expect(model.activeHistoryID == nil)
            model.persistCurrentOutput()
            #expect(model.history.isEmpty)
        }
    }
    @Test func retentionPersistsAndZeroDoesNotSaveNewCaptures() throws {
        try withModel { model, defaults, directory in
            model.setHistoryLimit(2)
            for n in 1...3 { model.acceptCapture(Data([UInt8(n)]), source: "Clip") }
            #expect(model.history.count == 2)
            #expect(AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false).historyLimit == 2)
            model.setHistoryLimit(0)
            model.acceptCapture(Data([9]), source: "Private")
            #expect(model.history.isEmpty)
            #expect(model.png == Data([9]))
            #expect(model.activeHistoryID == nil)
        }
    }
    @Test func clearHistoryDoesNotResaveActiveOutput() throws {
        try withModel { model, _, _ in
            model.acceptCapture(Data([1]), source: "Clip")
            model.output = "secret"; model.persistCurrentOutput()
            model.clearHistory(); model.persistCurrentOutput()
            #expect(model.history.isEmpty)
            #expect(model.png == nil)
            #expect(model.output.isEmpty)
        }
    }
    @Test func reopenedCaptureCanActuallyBeConvertedAgain() async throws {
        let name = "SmartClipboardTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let image = NSImage(size: NSSize(width: 900, height: 160))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 900, height: 160).fill()
        ("Reusable Capture 42" as NSString).draw(at: NSPoint(x: 40, y: 55), withAttributes: [.font: NSFont.systemFont(ofSize: 54), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false)
        model.acceptCapture(data, source: "Fixture")
        model.resultFormat = .markdown; model.output = "# Earlier result"; model.persistCurrentOutput()
        let saved = try #require(model.history.first)
        model.clear(); model.openHistory(saved, showWindow: false)
        model.convert(local: true)
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!model.busy)
        #expect(model.error == nil)
        #expect(model.output.contains("Reusable Capture 42"))
        #expect(model.savedConversions.map(\.format) == [.markdown, .text])
        #expect(model.png == data)
    }
    @Test func unavailableHistoryDoesNotPretendToSaveOrClear() throws {
        try withModel { _, defaults, directory in
            let index = directory.appendingPathComponent("index.json")
            try Data("corrupt".utf8).write(to: index)
            let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false)
            model.acceptCapture(Data([1]), source: "Unsaved")
            #expect(model.png == Data([1]))
            #expect(model.error?.contains("could not save history") == true)
            model.clearHistory()
            #expect(model.error?.contains("no files were deleted") == true)
            #expect(try String(contentsOf: index, encoding: .utf8) == "corrupt")
        }
    }
    @Test func pickItForMeCanBeConfiguredAsDefault() throws {
        try withModel { model, defaults, directory in
            model.defaultFormat = .auto
            model.acceptCapture(Data([1]), source: "Clip")
            #expect(model.format == .auto)
            #expect(model.format.title == "Auto detect")
            #expect(AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false).defaultFormat == .auto)
        }
    }
}
