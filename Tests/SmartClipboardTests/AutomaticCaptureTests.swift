import AppKit
import Testing
import ClipboardCore
@testable import SmartClipboard

@MainActor struct AutomaticCaptureTests {
    private func withModel(
        capture: CaptureClient? = nil,
        convert: @escaping (Data, OutputFormat, String, Bool) async throws -> ConversionResult = { _, _, _, _ in ConversionResult(format: .markdown, content: "# Captured") },
        test: (AppModel, NSPasteboard, UserDefaults) async throws -> Void
    ) async throws {
        let name = "AutomaticCaptureTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        defer { board.releaseGlobally(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        board.setString("Previous clipboard", forType: .string)
        let client = capture ?? CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in Data([1, 2, 3]) })
        let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false, captureClient: client, pasteboard: board, presentsWindows: false, conversionOverride: convert)
        try await test(model, board, defaults)
    }
    private func finish(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while (model.capturing || model.busy) && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.capturing && !model.busy)
    }
    @Test func preferredFormatAndDirectionAreSavedAndUsedForBothCaptureModes() async throws {
        for window in [false, true] {
            var modes: [Bool] = [], requests: [OutputFormat] = [], directions: [String] = []
            let client = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { modes.append($0); return Data([1, 2, 3]) })
            try await withModel(capture: client, convert: { _, format, direction, local in
                requests.append(format); directions.append(direction); #expect(!local)
                return ConversionResult(format: .json, content: "{\"count\":3}")
            }) { model, board, defaults in
                model.defaultFormat = .json; model.defaultInstruction = "Keep field names"
                model.copyAutomatically = false
                model.capture(window: window)
                model.defaultFormat = .yaml; model.defaultInstruction = "Changed while selecting"
                model.capture(window: !window) // Ignore a second capture while selecting.
                try await finish(model)
                #expect(modes == [window]); #expect(requests == [.json]); #expect(directions == ["Keep field names"])
                #expect(defaults.string(forKey: "defaultFormat") == OutputFormat.yaml.rawValue)
                #expect(defaults.string(forKey: "defaultInstruction") == "Changed while selecting")
                #expect(board.string(forType: .string) == "{\"count\":3}")
                #expect(model.history.count == 1)
                #expect(model.savedConversions.first?.format == .json)
                #expect(model.png == Data([1, 2, 3]))
                #expect(model.error == nil)
            }
        }
    }
    @Test func automaticSelectionCopiesResolvedFormatAndHistoryReopenDoesNotConvert() async throws {
        var calls = 0
        try await withModel(convert: { _, format, _, _ in
            calls += 1; #expect(format == .auto)
            return ConversionResult(format: .markdown, content: "# Captured")
        }) { model, board, _ in
            model.processImportedImage(Data([1]), source: "Imported screenshot")
            try await finish(model)
            #expect(board.string(forType: .string) == "# Captured")
            #expect(model.notice == "Markdown copied.")
            let entry = try #require(model.history.first)
            model.clear(); model.openHistory(entry, showWindow: false)
            #expect(calls == 1); #expect(model.output == "# Captured")
        }
    }
    @Test func imagePreferenceCopiesPNGWithoutAI() async throws {
        var calls = 0
        try await withModel(convert: { _, _, _, _ in calls += 1; throw ClipError.message("AI should not run") }) { model, board, _ in
            model.defaultFormat = .image; model.capture()
            try await finish(model)
            #expect(calls == 0); #expect(board.data(forType: .png) == Data([1, 2, 3]))
            #expect(model.notice == "Image copied.")
        }
    }
    @Test func failedConversionPreservesClipboardAndOriginalForRetry() async throws {
        try await withModel(convert: { _, _, _, _ in throw ClipError.message("Connection failed") }) { model, board, _ in
            model.capture(); try await finish(model)
            #expect(model.error == "Connection failed")
            #expect(board.string(forType: .string) == "Previous clipboard")
            #expect(model.png == Data([1, 2, 3])); #expect(model.history.count == 1)
            #expect(model.savedConversions.isEmpty)
        }
    }
    @Test func cancellationDuringAutomaticConversionDoesNotCopy() async throws {
        var started = false
        try await withModel(convert: { _, _, _, _ in
            started = true; try await Task.sleep(for: .seconds(30))
            return ConversionResult(format: .text, content: "Must not be copied")
        }) { model, board, _ in
            model.capture()
            let deadline = Date().addingTimeInterval(5)
            while !started && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(started); model.cancel(); try await finish(model)
            #expect(board.string(forType: .string) == "Previous clipboard")
            #expect(model.history.count == 1); #expect(model.savedConversions.isEmpty)
        }
    }
    @Test func cancelledSelectionDoesNotConvertOrAddHistory() async throws {
        var calls = 0
        let client = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in nil })
        try await withModel(capture: client, convert: { _, _, _, _ in calls += 1; throw ClipError.message("AI should not run") }) { model, board, _ in
            model.capture(); try await finish(model)
            #expect(calls == 0); #expect(model.history.isEmpty)
            #expect(board.string(forType: .string) == "Previous clipboard")
        }
    }
}
