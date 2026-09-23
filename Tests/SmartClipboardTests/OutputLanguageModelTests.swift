import AppKit
import Testing
import ClipboardCore
@testable import SmartClipboard

@MainActor struct OutputLanguageModelTests {
    private func withModel(
        capture: CaptureClient? = nil,
        systemLanguage: @escaping () -> String = { "it-IT" },
        configure: (UserDefaults, URL) throws -> Void = { _, _ in },
        convert: @escaping (Data, OutputFormat, String, Bool) async throws -> ConversionResult,
        test: (AppModel, NSPasteboard, UserDefaults, URL) async throws -> Void
    ) async throws {
        let name = "OutputLanguageModelTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        defer {
            board.releaseGlobally()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        board.setString("Previous clipboard", forType: .string)
        try configure(defaults, directory)
        let client = capture ?? CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in Data([1, 2, 3]) })
        let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false, captureClient: client,
                             pasteboard: board, presentsWindows: false, conversionOverride: convert, systemLanguage: systemLanguage)
        defer { model.cancel() }
        try await test(model, board, defaults, directory)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    private func finish(_ model: AppModel) async throws { try await waitFor { !model.busy && !model.capturing } }

    @Test func defaultKeepsSourceDespiteDifferentSystemLanguageAndCopiesAutomatically() async throws {
        var instructions: [String] = []
        try await withModel(convert: { _, _, instruction, _ in
            instructions.append(instruction)
            return ConversionResult(format: .text, content: "Hola mundo\nBonjour")
        }) { model, board, _, _ in
            #expect(model.defaultOutputLanguage == .source)
            model.copyAutomatically = false
            model.capture()
            try await finish(model)
            #expect(instructions == [OutputLanguage.instruction(userInstruction: "", resolvedIdentifier: nil)])
            #expect(board.string(forType: .string) == "Hola mundo\nBonjour")
            #expect(model.resultOutputLanguage == nil)
            #expect(model.savedConversions.count == 1)
            #expect(model.savedConversions[0].outputLanguage == nil)
            #expect(model.error == nil)
        }
    }

    @Test func upgradePreservesSavedDirectionsUntilAnExplicitLanguageIsChosen() async throws {
        var instructions: [String] = []
        try await withModel(configure: { defaults, _ in
            defaults.set("Translate to French", forKey: "defaultInstruction")
        }, convert: { _, _, instruction, _ in
            instructions.append(instruction)
            return ConversionResult(format: .text, content: "Bonjour")
        }) { model, _, defaults, directory in
            #expect(model.defaultOutputLanguage == .directions)
            #expect(defaults.string(forKey: "defaultOutputLanguage") == "directions")
            model.capture(); try await finish(model)
            #expect(instructions == ["Translate to French"])
            #expect(model.resultOutputLanguage == "und")
            model.defaultOutputLanguage = .source
            let restored = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false, presentsWindows: false)
            #expect(restored.defaultOutputLanguage == .source)
            #expect(restored.defaultInstruction == "Translate to French")
        }
    }

    @Test func reopeningLegacyHistoryRetainsItsTranslationDirection() async throws {
        var instructions: [String] = []
        try await withModel(configure: { _, directory in
            let history = try HistoryStore(directory: directory)
            let entry = try #require(try history.add(png: Data([1, 2, 3]), source: "Synthetic legacy capture"))
            try history.save(SavedConversion(format: .text, content: "Bonjour", instruction: "Translate to French"), for: entry.id)
            let index = directory.appendingPathComponent("index.json")
            var entries = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [[String: Any]])
            var conversions = try #require(entries[0]["conversions"] as? [[String: Any]])
            conversions[0].removeValue(forKey: "outputLanguage")
            entries[0]["conversions"] = conversions
            try JSONSerialization.data(withJSONObject: entries).write(to: index)
        }, convert: { _, _, instruction, _ in
            instructions.append(instruction)
            return ConversionResult(format: .text, content: "Bonjour encore")
        }) { model, board, _, _ in
            model.openHistory(try #require(model.history.first), showWindow: false)
            #expect(model.outputLanguage == .directions)
            #expect(model.instruction == "Translate to French")
            model.convert(); try await finish(model)
            #expect(instructions == ["Translate to French"])
            #expect(model.savedConversions.count == 1)
            #expect(model.savedConversions[0].outputLanguage == "und")
            #expect(board.string(forType: .string) == "Previous clipboard")
        }
    }

    @Test func captureSnapshotsSystemTargetBeforeSelectionAndSavesResolvedLanguage() async throws {
        var currentSystem = "fr-FR"
        var selection: CheckedContinuation<Data?, Never>?
        defer { selection?.resume(returning: nil) }
        let capture = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in
            await withCheckedContinuation { selection = $0 }
        })
        var instructions: [String] = []
        try await withModel(capture: capture, systemLanguage: { currentSystem }, convert: { _, _, instruction, _ in
            instructions.append(instruction)
            return ConversionResult(format: .text, content: "Bonjour")
        }) { model, board, defaults, directory in
            model.defaultOutputLanguage = .system
            model.defaultInstruction = "Keep line breaks"
            model.capture(window: true)
            try await waitFor { selection != nil }
            currentSystem = "de-DE"
            model.defaultOutputLanguage = .language("ja")
            let continuation = try #require(selection); selection = nil
            continuation.resume(returning: Data([1, 2, 3]))
            try await finish(model)
            #expect(instructions == [OutputLanguage.instruction(userInstruction: "Keep line breaks", resolvedIdentifier: "fr-FR")])
            #expect(board.string(forType: .string) == "Bonjour")
            #expect(model.resultOutputLanguage == "fr-FR")
            #expect(model.savedConversions[0].outputLanguage == "fr-FR")
            #expect(model.savedConversions[0].instruction == "Keep line breaks")
            #expect(defaults.string(forKey: "defaultOutputLanguage") == "language:ja")
            let restored = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false, presentsWindows: false)
            #expect(restored.defaultOutputLanguage == .language("ja"))
            #expect(restored.history[0].conversions[0].outputLanguage == "fr-FR")
        }
    }

    @Test func importSnapshotsTranslationBeforeItsTaskRuns() async throws {
        var systemLanguage = "es"
        var instructions: [String] = []
        try await withModel(systemLanguage: { systemLanguage }, convert: { _, _, instruction, _ in
            instructions.append(instruction)
            return ConversionResult(format: .text, content: "Hola")
        }) { model, _, _, _ in
            model.defaultOutputLanguage = .system
            model.processImportedImage(Data([9]), source: "Synthetic imported capture")
            systemLanguage = "en"
            model.defaultOutputLanguage = .source
            try await finish(model)
            #expect(instructions == [OutputLanguage.instruction(userInstruction: "", resolvedIdentifier: "es")])
            #expect(model.savedConversions.first?.outputLanguage == "es")
        }
    }

    @Test func historyReextractsOriginalIntoAnotherLanguageWithoutOverwritingOrCopying() async throws {
        var requests: [(Data, String)] = []
        try await withModel(convert: { data, _, instruction, _ in
            requests.append((data, instruction))
            return ConversionResult(format: .text, content: requests.count == 1 ? "Hola" : "Bonjour")
        }) { model, board, _, directory in
            model.defaultFormat = .text
            model.capture(); try await finish(model)
            let entry = try #require(model.history.first)
            let revision = board.changeCount
            model.clear(); model.openHistory(entry, showWindow: false)
            #expect(requests.count == 1)
            model.copyAutomatically = false
            model.outputLanguage = .language("fr")
            model.instruction = "Translate to German; keep paragraphs"
            model.convert()
            model.outputLanguage = .language("ja")
            try await finish(model)
            #expect(requests.count == 2)
            #expect(requests[0].0 == requests[1].0)
            #expect(requests[1].1 == OutputLanguage.instruction(userInstruction: "Translate to German; keep paragraphs", resolvedIdentifier: "fr"))
            #expect(board.changeCount == revision)
            #expect(model.savedConversions.map(\.outputLanguage) == [nil, "fr"])
            #expect(model.savedConversions.map(\.content) == ["Hola", "Bonjour"])
            #expect(model.resultOutputLanguage == "fr")
            model.output = "Bonjour modifié"; model.persistCurrentOutput()
            #expect(model.savedConversions.count == 2)
            #expect(model.savedConversions.last?.outputLanguage == "fr")
            let restored = try HistoryStore(directory: directory)
            #expect(restored.entries[0].conversions.map(\.content) == ["Hola", "Bonjour modifié"])
            model.useSavedConversion(model.savedConversions[0])
            #expect(model.outputLanguage == .source)
            #expect(model.resultOutputLanguage == nil)
            #expect(model.output == "Hola")
            model.useSavedConversion(try #require(model.savedConversions.last))
            #expect(model.outputLanguage == .language("fr"))
            #expect(model.instruction == "Translate to German; keep paragraphs")
        }
    }

    @Test func passThroughDoesNotTranslateOrCallAI() async throws {
        var calls = 0
        try await withModel(convert: { _, _, _, _ in
            calls += 1; throw ClipError.message("Should not run")
        }) { model, board, _, _ in
            model.defaultFormat = .image; model.defaultOutputLanguage = .language("ja")
            model.capture(); try await finish(model)
            #expect(calls == 0)
            #expect(board.data(forType: .png) == Data([1, 2, 3]))
            #expect(model.savedConversions.isEmpty)
            #expect(model.resultOutputLanguage == nil)
        }
    }

    @Test func onDeviceOCRKeepsSourceAndDoesNotClaimTranslation() async throws {
        var localInstructions: [String] = []
        try await withModel(convert: { _, _, instruction, local in
            #expect(local)
            localInstructions.append(instruction)
            return ConversionResult(format: .text, content: "Hola")
        }) { model, _, _, _ in
            model.acceptCapture(Data([1]), source: "Synthetic source")
            model.outputLanguage = .language("fr")
            model.instruction = "Keep line breaks"
            model.convert(local: true); try await finish(model)
            #expect(localInstructions == ["Keep line breaks"])
            #expect(model.resultOutputLanguage == nil)
            #expect(model.savedConversions[0].outputLanguage == nil)
            #expect(model.savedConversions[0].provenance?.providerID == "apple-vision")
        }
    }

    @Test func failedTranslationKeepsSourceHistoryAndClipboard() async throws {
        var calls = 0
        try await withModel(convert: { _, _, _, _ in
            calls += 1
            if calls == 1 { return ConversionResult(format: .text, content: "Hola") }
            throw ClipError.message("Provider unavailable")
        }) { model, board, _, _ in
            model.capture(); try await finish(model)
            model.outputLanguage = .language("fr")
            model.copyAutomatically = true
            model.convert(); try await finish(model)
            #expect(board.string(forType: .string) == "Hola")
            #expect(model.savedConversions.count == 1)
            #expect(model.savedConversions.first?.outputLanguage == nil)
            #expect(model.error == "Provider unavailable")
        }
    }
}
