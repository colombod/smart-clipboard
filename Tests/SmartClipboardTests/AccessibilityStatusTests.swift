import AppKit
import Combine
import ClipboardCore
import Testing
@testable import SmartClipboard

@MainActor private final class AccessibilityTestHotKeyBackend: HotKeyBackend {
    var handler: ((UInt32) -> Void)?
    func register(_ shortcut: Shortcut, id: UInt32) throws {}
    func unregister(_ id: UInt32) {}
}

@MainActor private final class AccessibilityAnnouncementCollector {
    var messages: [String] = []
}

@MainActor struct AccessibilityStatusTests {
    private func withObservedModel(
        convert: @escaping (Data, ConnectionProfile, OutputFormat, String) async throws -> ProviderConversion,
        test: (AppModel, NSPasteboard, AccessibilityAnnouncementCollector, Data) async throws -> Void
    ) async throws {
        let name = "AccessibilityStatusTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        defer {
            board.releaseGlobally()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        let capture = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in nil })
        let hotkeys = HotKeyManager(backend: AccessibilityTestHotKeyBackend(), systemShortcuts: { [] })
        let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false,
                             hotkeyManager: hotkeys, captureClient: capture, pasteboard: board,
                             presentsWindows: false, providerConversionOverride: convert)
        let collector = AccessibilityAnnouncementCollector()
        let announcer = AccessibilityStatusAnnouncer(isVoiceOverEnabled: { true }, post: { collector.messages.append($0) })
        // Use the same synchronous publishers as AppDelegate, with the real
        // AppModel's @Published ordering and a collector instead of live speech.
        let subscription = Publishers.CombineLatest4(model.$capturing, model.$busy,
                                                      model.$error.map { $0 != nil }, model.$operationNotice)
            .sink { state in
                announcer.observe(.init(capturing: state.0, processing: state.1, failed: state.2, notice: state.3))
            }
        defer { subscription.cancel(); model.cancel() }
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF8sAAAAASUVORK5CYII="))
        try await test(model, board, collector, png)
    }

    private func finish(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while (model.capturing || model.busy) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!model.capturing && !model.busy)
    }

    @Test func actualImportPublishersAnnounceRepeatedCopiesWithoutReadingPrivateContent() async throws {
        var calls = 0
        let privateResult = "PRIVATE RESULT 1294"
        try await withObservedModel(convert: { _, _, format, _ in
            calls += 1
            #expect(format == .text)
            return ProviderConversion(result: ConversionResult(format: .text, content: privateResult))
        }) { model, board, collector, png in
            #expect(collector.messages.isEmpty)
            let profile = ConnectionProfile(provider: .omlx, model: "mock-vision")
            for _ in 0..<2 {
                model.processImportedImage(png, source: "PRIVATE SOURCE.png", profile: profile,
                                           preferred: .text, direction: "PRIVATE DIRECTION")
                try await finish(model)
            }
            #expect(calls == 2)
            #expect(model.error == nil)
            #expect(model.history.count == 2)
            #expect(board.string(forType: .string) == privateResult)
            #expect(collector.messages == ["Processing your capture.", "Plain text copied. Ready to paste.",
                                           "Processing your capture.", "Plain text copied. Ready to paste."])
            model.output += " PRIVATE EDIT"
            model.instruction = "PRIVATE EDITED INSTRUCTION"
            model.refreshReadiness()
            #expect(collector.messages.count == 4)
            model.copyImage()
            #expect(board.data(forType: .png) == png)
            #expect(collector.messages.last == "Image copied. Ready to paste.")
            #expect(!collector.messages.contains(where: { $0.contains("PRIVATE") }))
        }
    }

    @Test func actualImportFailurePublishersAnnounceOnlyGenericActionableDetails() async throws {
        let providerFailure = "PRIVATE PROVIDER TOKEN 427; private captured account rejected"
        try await withObservedModel(convert: { _, _, _, _ in throw ClipError.message(providerFailure) }) { model, board, collector, png in
            board.setString("Previous private clipboard", forType: .string)
            let revision = board.changeCount
            model.processImportedImage(png, source: "PRIVATE SOURCE.png",
                                       profile: ConnectionProfile(provider: .omlx, model: "mock-vision"), preferred: .text)
            try await finish(model)
            #expect(model.error == providerFailure)
            #expect(board.changeCount == revision)
            #expect(board.string(forType: .string) == "Previous private clipboard")
            #expect(collector.messages == ["Processing your capture.",
                                           "Smart Clipboard needs attention. Open Clipboard from the menu bar for details."])
            model.error = "PRIVATE REVISED PROVIDER TOKEN"
            model.refreshReadiness()
            #expect(collector.messages.count == 2)
            #expect(!collector.messages.contains(where: { $0.contains("PRIVATE") }))
        }
    }

    @Test func startupAndRepeatedRefreshesAreSilent() {
        var spoken: [String] = []
        let announcer = AccessibilityStatusAnnouncer(isVoiceOverEnabled: { true }, post: { spoken.append($0) })
        let stale = AccessibilityStatusSnapshot(notice: .resultCopied(.markdown))
        announcer.observe(stale)
        for _ in 0..<10 { announcer.observe(stale) }
        #expect(spoken.isEmpty)
    }

    @Test func sameFormatSecondCaptureAnnouncesItsOwnCopy() {
        var spoken: [String] = []
        let announcer = AccessibilityStatusAnnouncer(isVoiceOverEnabled: { true }, post: { spoken.append($0) })
        announcer.observe(.init())
        for _ in 0..<2 {
            announcer.observe(.init(capturing: true))
            announcer.observe(.init())
            announcer.observe(.init(processing: true))
            announcer.observe(.init(processing: true, notice: .resultCopied(.markdown)))
            announcer.observe(.init(notice: .resultCopied(.markdown)))
            announcer.observe(.init(notice: .resultCopied(.markdown)))
        }
        #expect(spoken == Array(repeating: ["Select a region or window. Press Escape to cancel.",
                                           "Processing your capture.", "Markdown copied. Ready to paste."], count: 2).flatMap { $0 })
    }

    @Test func immediateImageCopyDoesNotNeedAProcessingPhase() {
        var spoken: [String] = []
        let announcer = AccessibilityStatusAnnouncer(isVoiceOverEnabled: { true }, post: { spoken.append($0) })
        announcer.observe(.init())
        for _ in 0..<2 {
            announcer.observe(.init(capturing: true))
            announcer.observe(.init(capturing: true, notice: .imageCopied))
            announcer.observe(.init(notice: .imageCopied))
        }
        #expect(spoken.filter { $0 == "Image copied. Ready to paste." }.count == 2)
        #expect(!spoken.contains("Conversion complete."))
    }

    @Test func manualCopyAndConversionWithoutAutomaticCopyAreAnnounced() {
        var spoken: [String] = []
        let announcer = AccessibilityStatusAnnouncer(isVoiceOverEnabled: { true }, post: { spoken.append($0) })
        announcer.observe(.init())
        announcer.observe(.init(processing: true))
        announcer.observe(.init())
        announcer.observe(.init(notice: .resultCopied(.text)))
        announcer.observe(.init(notice: .imageCopied))
        #expect(spoken == ["Processing your capture.", "Conversion complete.", "Plain text copied. Ready to paste.",
                           "Image copied. Ready to paste."])
    }

    @Test func cancellationsDoNotAlsoAnnounceCompletion() {
        var spoken: [String] = []
        let announcer = AccessibilityStatusAnnouncer(isVoiceOverEnabled: { true }, post: { spoken.append($0) })
        announcer.observe(.init())
        announcer.observe(.init(capturing: true))
        announcer.observe(.init(capturing: true, notice: .captureCancelled))
        announcer.observe(.init(notice: .captureCancelled))
        announcer.observe(.init(processing: true))
        announcer.observe(.init(processing: true, notice: .conversionCancelled))
        announcer.observe(.init(notice: .conversionCancelled))
        #expect(spoken == ["Select a region or window. Press Escape to cancel.", "Capture cancelled.",
                           "Processing your capture.", "Conversion cancelled."])
    }

    @Test func failureUsesOnlyGenericMetadataAndDeduplicates() {
        var spoken: [String] = []
        let announcer = AccessibilityStatusAnnouncer(isVoiceOverEnabled: { true }, post: { spoken.append($0) })
        announcer.observe(.init())
        announcer.observe(.init(processing: true))
        announcer.observe(.init(processing: true, failed: true))
        announcer.observe(.init(failed: true))
        announcer.observe(.init(failed: true))
        #expect(spoken == ["Processing your capture.", AccessibilityStatusSnapshot.failureMessage])
        #expect(AccessibilityStatusSnapshot(failed: true).accessibilityValue(ready: true, preferredFormat: .text)
                == AccessibilityStatusSnapshot.failureMessage)
    }

    @Test func arbitraryNoticesNeverBecomeSpeechOrAccessibilityValues() async throws {
        try await withObservedModel(convert: { _, _, _, _ in
            ProviderConversion(result: ConversionResult(format: .text, content: "Unused"))
        }) { model, _, collector, _ in
            for notice in ["Saved private-account-number.png.", "copied SECRET TOKEN", "Markdown copied. SECRET TOKEN",
                           "Image copied.", "Provider error with private capture text"] {
                model.notice = notice
                let state = AccessibilityStatusSnapshot(notice: model.operationNotice)
                #expect(state.notice == .none)
                #expect(state.accessibilityValue(ready: true, preferredFormat: .json) == "Ready. Preferred format: JSON.")
            }
            #expect(collector.messages.isEmpty)
        }
    }

    @Test func enablingVoiceOverDoesNotReplayOffStateOutcomes() {
        var enabled = false
        var spoken: [String] = []
        let announcer = AccessibilityStatusAnnouncer(isVoiceOverEnabled: { enabled }, post: { spoken.append($0) })
        announcer.observe(.init())
        announcer.observe(.init(processing: true))
        announcer.observe(.init(processing: true, notice: .resultCopied(.json)))
        announcer.observe(.init(notice: .resultCopied(.json)))
        enabled = true
        announcer.observe(.init(notice: .resultCopied(.json)))
        #expect(spoken.isEmpty)
        announcer.observe(.init(processing: true))
        announcer.observe(.init(processing: true, notice: .resultCopied(.json)))
        announcer.observe(.init(notice: .resultCopied(.json)))
        #expect(spoken == ["Processing your capture.", "JSON copied. Ready to paste."])
    }

    @Test func statusValueReportsCurrentOperationAndSafeReadyState() {
        #expect(AccessibilityStatusSnapshot(capturing: true).accessibilityValue(ready: true, preferredFormat: .text)
                == "Select a region or window. Press Escape to cancel.")
        #expect(AccessibilityStatusSnapshot(capturing: true, processing: true).accessibilityValue(ready: true, preferredFormat: .text)
                == "Processing your capture.")
        #expect(AccessibilityStatusSnapshot().accessibilityValue(ready: false, preferredFormat: .text) == "Setup needs attention.")
    }
}
