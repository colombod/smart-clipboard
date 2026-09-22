import AppKit
import Testing
import ClipboardCore
@testable import SmartClipboard

@MainActor struct ProviderCaptureTests {
    private func withModel(
        capture: CaptureClient? = nil,
        convert: @escaping (Data, ConnectionProfile, OutputFormat, String) async throws -> ProviderConversion,
        test: (AppModel, NSPasteboard, URL) async throws -> Void
    ) async throws {
        let name = "ProviderCaptureTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        defer {
            board.releaseGlobally()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        board.setString("Previous clipboard", forType: .string)
        let client = capture ?? CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in Data([1, 2, 3]) })
        let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false, captureClient: client,
                             pasteboard: board, presentsWindows: false, providerConversionOverride: convert)
        model.defaultFormat = .text
        defer { model.cancel() }
        try await test(model, board, directory)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    private func finish(_ model: AppModel) async throws {
        try await waitFor { !model.capturing && !model.busy }
    }

    @Test func captureKeepsProviderAndCredentialReferenceChosenBeforeSelection() async throws {
        var selection: CheckedContinuation<Data?, Never>?
        defer { selection?.resume(returning: nil) }
        var requests: [ConnectionProfile] = []
        var requestedFormats: [OutputFormat] = []
        var requestedInstructions: [String] = []
        let client = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in
            await withCheckedContinuation { selection = $0 }
        })
        try await withModel(capture: client, convert: { _, profile, format, instruction in
            requests.append(profile)
            requestedFormats.append(format)
            requestedInstructions.append(instruction)
            return ProviderConversion(result: ConversionResult(format: .json, content: "{\"count\":3}"), model: "resolved-before-selection")
        }) { model, board, _ in
            let original = ConnectionProfile(provider: .anthropic, model: "chosen-before-selection")
            model.connections.update(original)
            model.connections.activeProvider = .anthropic
            model.defaultFormat = .json
            model.defaultInstruction = "Keep field names"
            model.capture()
            try await waitFor { selection != nil }
            let resumeSelection = try #require(selection)
            selection = nil
            model.connections.update(ConnectionProfile(provider: .anthropic, model: "changed-during-selection"))
            model.connections.update(ConnectionProfile(provider: .google, model: "another-provider"))
            model.connections.activeProvider = .google
            model.defaultFormat = .yaml
            model.defaultInstruction = "Changed while selecting"
            resumeSelection.resume(returning: Data([1, 2, 3]))
            try await finish(model)

            #expect(requests == [original])
            #expect(requests.first?.credentialAccount == original.credentialAccount)
            #expect(requests.first?.credentialAccount != model.connections.activeProfile.credentialAccount)
            #expect(requestedFormats == [.json])
            #expect(requestedInstructions == ["Keep field names"])
            #expect(board.string(forType: .string) == "{\"count\":3}")
            let provenance = try #require(model.savedConversions.first?.provenance)
            #expect(provenance == ConversionProvenance(providerID: "anthropic", profileID: original.id,
                                                       requestedModel: original.model, effectiveModel: "resolved-before-selection"))
            #expect(model.error == nil)
        }
    }

    @Test func importsSnapshotProviderButHistoryReconversionUsesCurrentProviderEvenForSameText() async throws {
        var requests: [ConnectionProfile] = []
        try await withModel(convert: { _, profile, _, _ in
            requests.append(profile)
            return ProviderConversion(result: ConversionResult(format: .text, content: "Same extracted text"), model: profile.model + "-resolved")
        }) { model, board, directory in
            let original = ConnectionProfile(provider: .anthropic, model: "first-model")
            let next = ConnectionProfile(provider: .google, model: "second-model")
            model.connections.update(original)
            model.connections.update(next)
            model.connections.activeProvider = .anthropic
            model.processImportedImage(Data([3, 2, 1]), source: "Imported screenshot")
            // The conversion Task has not run yet; changing Settings must not change this import.
            model.connections.activeProvider = .google
            try await finish(model)
            #expect(requests == [original])
            #expect(model.savedConversions.first?.provenance?.providerID == "anthropic")

            let entry = try #require(model.history.first)
            model.clear()
            board.clearContents()
            board.setString("Clipboard changed elsewhere", forType: .string)
            let clipboardRevision = board.changeCount
            model.openHistory(entry, showWindow: false)
            model.useSavedConversion(try #require(model.savedConversions.first))
            #expect(requests.count == 1)
            #expect(board.changeCount == clipboardRevision)
            #expect(board.string(forType: .string) == "Clipboard changed elsewhere")
            #expect(model.output == "Same extracted text")

            model.copyAutomatically = false
            model.convert()
            try await finish(model)
            #expect(requests == [original, next])
            #expect(model.savedConversions.count == 1)
            let expected = ConversionProvenance(providerID: "google", profileID: next.id,
                                                requestedModel: next.model, effectiveModel: "second-model-resolved")
            #expect(model.savedConversions.first?.provenance == expected)
            #expect(model.savedConversions.first?.content == "Same extracted text")
            #expect(board.changeCount == clipboardRevision)
            let reopened = try HistoryStore(directory: directory)
            #expect(reopened.entries.first?.conversions.first?.provenance == expected)
        }
    }

    @Test func importUsesPreferencesSavedBeforeFilePicker() async throws {
        var requests: [(ConnectionProfile, OutputFormat, String)] = []
        try await withModel(convert: { _, profile, format, instruction in
            requests.append((profile, format, instruction))
            return ProviderConversion(result: ConversionResult(format: format, content: "Imported text"))
        }) { model, board, _ in
            let beforePicker = ConnectionProfile(provider: .anthropic, model: "original-model")
            model.connections.activeProvider = .google
            model.defaultFormat = .json
            model.defaultInstruction = "Changed after the picker opened"
            model.processImportedImage(Data([1]), source: "Import", profile: beforePicker, preferred: .text, direction: "Original instruction")
            try await finish(model)
            #expect(requests.count == 1)
            #expect(requests.first?.0 == beforePicker)
            #expect(requests.first?.1 == .text)
            #expect(requests.first?.2 == "Original instruction")
            #expect(board.string(forType: .string) == "Imported text")
        }
    }

    @Test func editingSavedOutputRetainsItsOriginAfterProviderChanges() async throws {
        var calls = 0
        try await withModel(convert: { _, _, _, _ in
            calls += 1
            return ProviderConversion(result: ConversionResult(format: .text, content: "Original text"), model: "resolved-source-model")
        }) { model, _, directory in
            let origin = ConnectionProfile(provider: .anthropic, model: "source-model")
            model.connections.update(origin)
            model.connections.activeProvider = .anthropic
            model.processImportedImage(Data([1]), source: "Editable capture")
            try await finish(model)
            model.connections.activeProvider = .google
            model.output = "Edited by the user"
            model.persistCurrentOutput()
            let expected = ConversionProvenance(providerID: "anthropic", profileID: origin.id,
                                                requestedModel: origin.model, effectiveModel: "resolved-source-model", userEdited: true)
            #expect(model.savedConversions.first?.provenance == expected)
            #expect(model.resultOrigin?.contains("Edited") == true)
            let reopened = try HistoryStore(directory: directory)
            let entry = try #require(reopened.entries.first)
            #expect(entry.conversions.first?.provenance == expected)
            model.clear()
            model.openHistory(entry, showWindow: false)
            #expect(model.output == "Edited by the user")
            #expect(model.savedConversions.first?.provenance == expected)
            #expect(calls == 1)

            model.acceptCapture(Data([2]), source: "A different capture")
            #expect(model.resultOrigin == nil)
            model.output = "A manually entered result"
            model.persistCurrentOutput()
            #expect(model.savedConversions.first?.provenance == nil)
        }
    }

    @Test func cancelledConversionCannotCopyOrSaveALateProviderResponse() async throws {
        var pending: CheckedContinuation<ProviderConversion, Never>?
        let late = ProviderConversion(result: ConversionResult(format: .text, content: "Must not be copied"), model: "late-model")
        defer { pending?.resume(returning: late) }
        try await withModel(convert: { _, _, _, _ in
            // Deliberately ignore cancellation until the simulated provider returns.
            await withCheckedContinuation { pending = $0 }
        }) { model, board, _ in
            model.processImportedImage(Data([1, 2, 3]), source: "Cancelled conversion")
            try await waitFor { pending != nil }
            let response = try #require(pending)
            pending = nil
            model.cancel()
            response.resume(returning: late)
            try await finish(model)
            #expect(board.string(forType: .string) == "Previous clipboard")
            #expect(model.output.isEmpty)
            #expect(model.savedConversions.isEmpty)
            #expect(model.history.count == 1)
            #expect(model.png == Data([1, 2, 3]))
            #expect(model.notice == "Conversion cancelled.")
        }
    }

    @Test func imagePassThroughNeverCallsAProvider() async throws {
        var calls = 0
        try await withModel(convert: { _, _, _, _ in
            calls += 1
            throw ClipError.message("Provider should not be used for image pass-through")
        }) { model, board, _ in
            let image = Data([4, 5, 6])
            model.connections.activeProvider = .google
            model.defaultFormat = .image
            model.processImportedImage(image, source: "Pass-through image")
            try await finish(model)
            #expect(board.data(forType: .png) == image)
            model.format = .image
            model.convert()
            #expect(calls == 0)
            #expect(!model.busy)
            #expect(model.savedConversions.isEmpty)
            #expect(model.error == nil)
        }
    }
}
