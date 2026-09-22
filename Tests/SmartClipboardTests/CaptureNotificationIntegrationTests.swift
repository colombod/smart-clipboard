import AppKit
import Testing
import ClipboardCore
@testable import SmartClipboard

// Injected capture/conversion and private pasteboards verify event ordering.
// Native shortcut capture and delivered macOS banners still need packaged-app UAT.
@MainActor struct CaptureNotificationIntegrationTests {
    private struct RecordedFeedback {
        let event: CaptureFeedback
        let textAtDelivery: String?
        let imageAtDelivery: Data?
    }

    @MainActor private final class Recorder {
        var deliveries: [RecordedFeedback] = []
        var events: [CaptureFeedback] { deliveries.map(\.event) }
    }

    private func withModel(
        capture: CaptureClient? = nil,
        configureDefaults: (UserDefaults) -> Void = { _ in },
        unavailableHistory: Bool = false,
        convert: @escaping (Data, OutputFormat, String, Bool) async throws -> ConversionResult = { _, _, _, _ in
            ConversionResult(format: .markdown, content: "# Private extracted text")
        },
        test: (AppModel, NSPasteboard, Recorder) async throws -> Void
    ) async throws {
        let name = "CaptureNotificationIntegrationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        defer {
            board.releaseGlobally()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        configureDefaults(defaults)
        if unavailableHistory { try Data([0]).write(to: directory) }
        board.setString("Previous private clipboard", forType: .string)
        let client = capture ?? CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in Data([1, 2, 3]) })
        let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false,
                             captureClient: client, pasteboard: board, presentsWindows: false, conversionOverride: convert)
        let recorder = Recorder()
        model.operationFeedback = { event in
            recorder.deliveries.append(RecordedFeedback(event: event, textAtDelivery: board.string(forType: .string),
                                                       imageAtDelivery: board.data(forType: .png)))
        }
        defer { model.cancel() }
        try await test(model, board, recorder)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    private func finish(_ model: AppModel) async throws {
        try await waitFor { !model.capturing && !model.busy }
    }

    @Test func regionAndWindowNotifyOnceAfterResolvedOutputIsOnClipboard() async throws {
        for window in [false, true] {
            try await withModel { model, board, recorder in
                model.defaultFormat = .auto
                model.capture(window: window)
                model.capture(window: !window) // A second request while selecting is ignored.
                #expect(recorder.events.isEmpty)
                try await finish(model)
                #expect(recorder.events == [.copied(.markdown)])
                #expect(recorder.deliveries.first?.textAtDelivery == "# Private extracted text")
                #expect(board.string(forType: .string) == "# Private extracted text")
            }
        }
    }

    @Test func passThroughNotifiesAfterPNGWriteWithoutRunningAI() async throws {
        var providerCalls = 0
        try await withModel(convert: { _, _, _, _ in
            providerCalls += 1
            throw ClipError.message("Pass-through must not use AI")
        }) { model, board, recorder in
            model.defaultFormat = .image
            model.capture()
            try await finish(model)
            #expect(providerCalls == 0)
            #expect(recorder.events == [.copied(.image)])
            #expect(recorder.deliveries.first?.imageAtDelivery == Data([1, 2, 3]))
            #expect(board.data(forType: .png) == Data([1, 2, 3]))
        }
    }

    @Test func importNotifiesOnceButOpeningSavedResultDoesNot() async throws {
        try await withModel { model, board, recorder in
            model.processImportedImage(Data([3, 2, 1]), source: "Private filename.png")
            try await finish(model)
            #expect(recorder.events == [.copied(.markdown)])
            #expect(recorder.deliveries.first?.textAtDelivery == "# Private extracted text")
            let entry = try #require(model.history.first)
            model.clear()
            board.clearContents()
            board.setString("Clipboard changed elsewhere", forType: .string)
            model.openHistory(entry, showWindow: false)
            model.useSavedConversion(try #require(model.savedConversions.first))
            #expect(recorder.events == [.copied(.markdown)])
            #expect(board.string(forType: .string) == "Clipboard changed elsewhere")
        }
    }

    @Test func conversionWithoutAutomaticCopyIsSilentUntilExplicitCopy() async throws {
        try await withModel { model, board, recorder in
            model.acceptCapture(Data([1]), source: "Private source")
            model.copyAutomatically = false
            model.convert()
            try await finish(model)
            #expect(recorder.events.isEmpty)
            #expect(board.string(forType: .string) == "Previous private clipboard")
            model.copyOutput()
            #expect(recorder.events == [.copied(.markdown)])
            #expect(recorder.deliveries.first?.textAtDelivery == "# Private extracted text")
        }
    }

    @Test func explicitImageCopyNotifiesOnceAfterWrite() async throws {
        try await withModel { model, _, recorder in
            model.acceptCapture(Data([7, 8, 9]), source: "Private image")
            #expect(recorder.events.isEmpty)
            model.copyImage()
            #expect(recorder.events == [.copied(.image)])
            #expect(recorder.deliveries.first?.imageAtDelivery == Data([7, 8, 9]))
        }
    }

    @Test func providerFailuresEmitOnlyGenericFailureAndPreserveClipboard() async throws {
        for operation in ["capture", "import", "convert"] {
            try await withModel(convert: { _, _, _, _ in
                throw ClipError.message("Private provider error, source text and credential-like detail")
            }) { model, board, recorder in
                if operation == "capture" { model.capture() }
                else if operation == "import" { model.processImportedImage(Data([1]), source: "Secret source.png") }
                else { model.acceptCapture(Data([1]), source: "Secret source"); model.convert() }
                try await finish(model)
                #expect(recorder.events == [.failed])
                #expect(recorder.deliveries.first?.textAtDelivery == "Previous private clipboard")
                #expect(board.string(forType: .string) == "Previous private clipboard")
            }
        }
    }

    @Test func deniedScreenPermissionFailsOnceWithoutTakingImageOrChangingClipboard() async throws {
        var captures = 0
        let client = CaptureClient(hasAccess: { false }, requestAccess: { false }, takeImage: { _ in captures += 1; return Data([1]) })
        try await withModel(capture: client) { model, board, recorder in
            model.capture()
            try await finish(model)
            #expect(captures == 0)
            #expect(recorder.events == [.failed])
            #expect(board.string(forType: .string) == "Previous private clipboard")
        }
    }

    @Test func unreadableConnectionFailsBeforeCaptureAndEmitsNoDuplicate() async throws {
        var captures = 0
        let client = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in captures += 1; return Data([1]) })
        try await withModel(capture: client, configureDefaults: { defaults in
            defaults.set(Data("not valid settings".utf8), forKey: ConnectionStore.settingsKey)
        }) { model, board, recorder in
            model.capture()
            #expect(!model.capturing && !model.busy)
            #expect(captures == 0)
            #expect(recorder.events == [.failed])
            #expect(board.string(forType: .string) == "Previous private clipboard")
        }
    }

    @Test func escapedSelectionEmitsNothingAndKeepsClipboard() async throws {
        let client = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in nil })
        try await withModel(capture: client) { model, board, recorder in
            model.capture()
            try await finish(model)
            #expect(recorder.events.isEmpty)
            #expect(board.string(forType: .string) == "Previous private clipboard")
        }
    }

    @Test func cancellationSuppressesLateSuccessAndOrdinaryErrorForEveryConversionEntry() async throws {
        for operation in ["capture", "import", "convert"] {
            for fails in [false, true] {
                var pending: CheckedContinuation<ConversionResult, Error>?
                defer { pending?.resume(throwing: CancellationError()) }
                try await withModel(convert: { _, _, _, _ in
                    try await withCheckedThrowingContinuation { pending = $0 }
                }) { model, board, recorder in
                    if operation == "capture" { model.capture() }
                    else if operation == "import" { model.processImportedImage(Data([1]), source: "Cancel import") }
                    else {
                        model.acceptCapture(Data([1]), source: "Cancel conversion")
                        model.copyAutomatically = true
                        model.convert()
                    }
                    try await waitFor { pending != nil }
                    let response = try #require(pending)
                    pending = nil
                    model.cancel()
                    if fails { response.resume(throwing: ClipError.message("Late non-cancellation network error")) }
                    else { response.resume(returning: ConversionResult(format: .text, content: "Late private output")) }
                    try await finish(model)
                    #expect(recorder.events.isEmpty)
                    #expect(board.string(forType: .string) == "Previous private clipboard")
                    #expect(model.savedConversions.isEmpty)
                }
            }
        }
    }

    @Test func immediatelyCancelledImportedImageDoesNotCopyOrNotify() async throws {
        try await withModel { model, board, recorder in
            model.defaultFormat = .image
            model.processImportedImage(Data([1, 2, 3]), source: "Cancelled before its task starts")
            model.cancel()
            try await finish(model)
            #expect(recorder.events.isEmpty)
            #expect(board.string(forType: .string) == "Previous private clipboard")
            #expect(model.history.isEmpty)
        }
    }

    @Test func historyWarningDoesNotTurnSuccessfulCopyIntoFailure() async throws {
        try await withModel(unavailableHistory: true) { model, board, recorder in
            model.processImportedImage(Data([1]), source: "Unsaved source")
            try await finish(model)
            #expect(model.error?.contains("history") == true)
            #expect(model.history.isEmpty)
            #expect(board.string(forType: .string) == "# Private extracted text")
            #expect(recorder.events == [.copied(.markdown)])
            #expect(recorder.deliveries.first?.textAtDelivery == "# Private extracted text")
        }
    }
}
