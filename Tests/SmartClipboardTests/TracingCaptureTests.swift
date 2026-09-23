import AppKit
import Testing
import ClipboardCore
@testable import SmartClipboard

@MainActor struct TracingCaptureTests {
    private let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 40 40\"><path fill=\"#308060\" d=\"M0 0H40V40H0Z\"/></svg>"

    private func withModel(
        brokenConnection: Bool = true,
        capture: CaptureClient? = nil,
        trace: @escaping (Data, TraceSettings) async throws -> VectorTraceResult,
        test: (AppModel, NSPasteboard, URL, UserDefaults) async throws -> Void
    ) async throws {
        let name = "TracingCaptureTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        defer {
            board.releaseGlobally(); defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        if brokenConnection { defaults.set(Data("broken".utf8), forKey: ConnectionStore.settingsKey) }
        board.setString("Previous clipboard", forType: .string)
        let client = capture ?? CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in Data([1, 2, 3]) })
        let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false,
                             captureClient: client, pasteboard: board, presentsWindows: false,
                             providerConversionOverride: { _, _, _, _ in
                                 Issue.record("Local tracing called an AI provider")
                                 throw ClipError.message("Unexpected AI request")
                             }, traceOverride: trace)
        model.defaultFormat = .svg; model.defaultSVGMethod = .trace
        defer { model.cancel() }
        try await test(model, board, directory, defaults)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
    private func finish(_ model: AppModel) async throws { try await waitFor { !model.busy && !model.capturing } }

    @Test func regionAndWindowTraceWithoutReadableAISettingsAndIgnoreTranslation() async throws {
        var modes: [Bool] = []
        var settings: [TraceSettings] = []
        let client = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { window in
            modes.append(window); return Data([1])
        })
        try await withModel(capture: client, trace: { _, chosen in
            settings.append(chosen); return VectorTraceResult(svg: svg, engineVersion: "0.6.5")
        }) { model, board, _, _ in
            #expect(model.connections.configurationWarning != nil)
            model.defaultOutputLanguage = .language("fr")
            model.defaultInstruction = "Translate into French and remove the background"
            var feedback: [CaptureFeedback] = []
            model.operationFeedback = { feedback.append($0) }
            for window in [false, true] {
                model.capture(window: window); try await finish(model)
                #expect(board.string(forType: .string) == svg)
                #expect(model.outputLanguage == .source)
                #expect(model.resultOutputLanguage == nil)
                #expect(model.savedConversions.first?.instruction == "")
                #expect(model.savedConversions.first?.method == .vtracer)
                #expect(model.savedConversions.first?.provenance?.providerID == "vtracer")
                #expect(model.resultOrigin?.contains("VTracer 0.6.5") == true)
                #expect(model.error == nil)
            }
            #expect(modes == [false, true])
            #expect(settings == [TraceSettings(), TraceSettings()])
            #expect(feedback == [.copied(.svg), .copied(.svg)])
        }
    }

    @Test func captureSnapshotsTraceMethodPresetAndDetailBeforeSelection() async throws {
        var pending: CheckedContinuation<Data?, Never>?
        defer { pending?.resume(returning: nil) }
        var requests: [TraceSettings] = []
        let client = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in
            await withCheckedContinuation { pending = $0 }
        })
        try await withModel(capture: client, trace: { _, chosen in
            requests.append(chosen); return VectorTraceResult(svg: svg, engineVersion: "0.6.5")
        }) { model, board, _, _ in
            let chosen = TraceSettings(preset: .logo, detail: .detailed)
            model.defaultTraceSettings = chosen
            model.capture()
            try await waitFor { pending != nil }
            model.defaultSVGMethod = .ai; model.defaultFormat = .text
            model.defaultTraceSettings = TraceSettings(preset: .lineArt, detail: .balanced)
            let continuation = try #require(pending); pending = nil
            continuation.resume(returning: Data([1]))
            try await finish(model)
            #expect(requests == [chosen])
            #expect(model.traceSettings == chosen)
            #expect(model.svgMethod == .trace)
            #expect(board.string(forType: .string) == svg)
        }
    }

    @Test func cancelledTraceCannotSaveOrCopyLateResultAndCanRecover() async throws {
        var pending: CheckedContinuation<VectorTraceResult, Never>?
        defer { pending?.resume(returning: VectorTraceResult(svg: svg, engineVersion: "0.6.5")) }
        var calls = 0
        try await withModel(trace: { _, _ in
            calls += 1
            if calls == 1 { return await withCheckedContinuation { pending = $0 } }
            return VectorTraceResult(svg: svg, engineVersion: "0.6.5")
        }) { model, board, _, _ in
            model.processImportedImage(Data([1]), source: "Cancelled trace")
            try await waitFor { pending != nil }
            model.cancel()
            let response = try #require(pending); pending = nil
            response.resume(returning: VectorTraceResult(svg: svg, engineVersion: "0.6.5"))
            try await finish(model)
            #expect(board.string(forType: .string) == "Previous clipboard")
            #expect(model.savedConversions.isEmpty)
            #expect(model.output.isEmpty)
            model.processImportedImage(Data([2]), source: "Recovery trace")
            try await finish(model)
            #expect(board.string(forType: .string) == svg)
            #expect(model.error == nil)
        }
    }

    @Test func invalidOrFailedTracePreservesClipboardAndOriginal() async throws {
        for invalid in [true, false] {
            try await withModel(trace: { _, _ in
                if invalid { return VectorTraceResult(svg: "<svg><script>alert(1)</script></svg>", engineVersion: "0.6.5") }
                throw ClipError.message("Controlled tracing failure")
            }) { model, board, _, _ in
                var feedback: [CaptureFeedback] = []
                model.operationFeedback = { feedback.append($0) }
                model.capture(); try await finish(model)
                #expect(board.string(forType: .string) == "Previous clipboard")
                #expect(model.png == Data([1, 2, 3]))
                #expect(model.savedConversions.isEmpty)
                #expect(model.error != nil)
                #expect(feedback == [.failed])
            }
        }
    }

    @Test func historyRetainsAIAndTraceVariantsWithoutCallingToolsOrChangingClipboard() async throws {
        var calls = 0
        try await withModel(trace: { _, _ in
            calls += 1; return VectorTraceResult(svg: svg, engineVersion: "0.6.5")
        }) { model, board, directory, defaults in
            model.processImportedImage(Data([1]), source: "History trace")
            try await finish(model)
            let entry = try #require(model.history.first)
            let store = try HistoryStore(directory: directory)
            try store.save(SavedConversion(format: .svg, content: svg, instruction: "", method: .ai), for: entry.id)
            let second = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false,
                                  pasteboard: board, presentsWindows: false,
                                  traceOverride: { _, _ in calls += 1; return VectorTraceResult(svg: svg, engineVersion: "0.6.5") })
            #expect(second.defaultSVGMethod == .trace)
            board.clearContents(); board.setString("Do not replace this", forType: .string)
            let revision = board.changeCount
            second.openHistory(try #require(second.history.first), showWindow: false)
            #expect(second.savedConversions.count == 2)
            second.useSavedConversion(try #require(second.savedConversions.first { $0.method == .vtracer }))
            #expect(second.svgMethod == .trace)
            #expect(second.output == svg)
            #expect(calls == 1)
            #expect(board.changeCount == revision)
            second.traceSettings = TraceSettings(preset: .logo, detail: .detailed)
            second.convert(); try await finish(second)
            #expect(second.savedConversions.count == 3)
            #expect(board.changeCount == revision)
            #expect(calls == 2)
        }
    }

    @Test func imagePassThroughSkipsTraceDespiteSavedTraceMethod() async throws {
        try await withModel(trace: { _, _ in
            Issue.record("Pass through called tracer"); throw ClipError.message("Unexpected trace")
        }) { model, board, _, _ in
            model.defaultFormat = .image
            model.processImportedImage(Data([1, 2, 3]), source: "Pass through")
            try await finish(model)
            #expect(board.data(forType: .png) == Data([1, 2, 3]))
            #expect(model.error == nil)
        }
    }

    @Test func unreadableSavedTraceKeepsOriginalAvailableForRetry() async throws {
        let large = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 40 40\">" + String(repeating: "<path d=\"M0 0H40V40H0Z\"/>", count: 4000) + "</svg>"
        try await withModel(trace: { _, _ in VectorTraceResult(svg: large, engineVersion: "0.6.5") }) { model, board, directory, defaults in
            model.processImportedImage(Data([1, 2, 3]), source: "Retained original")
            try await finish(model)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let artifact = try #require(files.first { $0.lastPathComponent.hasPrefix("result-") })
            try FileManager.default.removeItem(at: artifact)
            let reopened = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false,
                                    pasteboard: board, presentsWindows: false,
                                    traceOverride: { _, _ in VectorTraceResult(svg: svg, engineVersion: "0.6.5") })
            let revision = board.changeCount
            reopened.openHistory(try #require(reopened.history.first), showWindow: false)
            #expect(reopened.png == Data([1, 2, 3]))
            #expect(reopened.activeHistoryID != nil)
            #expect(reopened.error != nil)
            #expect(reopened.output.isEmpty)
            #expect(board.changeCount == revision)
            reopened.convert(); try await finish(reopened)
            #expect(reopened.error == nil)
            #expect(reopened.output == svg)
            #expect(board.changeCount == revision)
        }
    }

    @Test func existingSVGPreferencesKeepAIOnUpgrade() throws {
        let name = "TracingMigration." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
        defaults.set("svg", forKey: "defaultFormat")
        let model = AppModel(defaults: defaults, historyDirectory: folder, registerHotkeys: false, presentsWindows: false)
        #expect(model.defaultSVGMethod == .ai)
        #expect(!model.defaultUsesTracing)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SMART_CLIPBOARD_TRACE_FIXTURE"] != nil && ProcessInfo.processInfo.environment["SMART_CLIPBOARD_TRACE_HELPER"] != nil))
    func actualPhotoTraceCopiesAndReopensLargeArtifactWithNoAI() async throws {
        let fixture = try #require(ProcessInfo.processInfo.environment["SMART_CLIPBOARD_TRACE_FIXTURE"])
        let executable = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SMART_CLIPBOARD_TRACE_HELPER"]))
        let png = try Data(contentsOf: URL(fileURLWithPath: fixture))
        try await withModel(trace: { png, settings in
            try await VectorTraceService(executable: executable).trace(png: png, settings: settings)
        }) { model, board, directory, defaults in
            model.defaultTraceSettings = TraceSettings(preset: .photo, detail: .detailed)
            model.processImportedImage(png, source: "Public photo trace acceptance fixture")
            let deadline = Date().addingTimeInterval(90)
            while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            #expect(!model.busy)
            #expect(model.error == nil)
            let output = try #require(board.string(forType: .string))
            #expect(output == model.output)
            #expect(output.utf8.count > 131_072)
            try SVGValidator.validate(output)
            let indexBytes = try Data(contentsOf: directory.appendingPathComponent("index.json")).count
            #expect(indexBytes < 10_000)
            let reopened = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false, pasteboard: board, presentsWindows: false)
            let revision = board.changeCount
            reopened.openHistory(try #require(reopened.history.first), showWindow: false)
            #expect(reopened.output == output)
            #expect(reopened.traceSettings == TraceSettings(preset: .photo, detail: .detailed))
            #expect(board.changeCount == revision)
        }
    }
}
