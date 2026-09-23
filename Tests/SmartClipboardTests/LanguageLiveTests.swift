import AppKit
import Testing
import ClipboardCore
@testable import SmartClipboard

/// Opt-in synthetic-image evidence only; never reads the screen or the general clipboard.
@MainActor struct LanguageLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SMART_CLIPBOARD_LANGUAGE_TEST_URL"] != nil))
    func localModelPreservesSpanishAndKeepsEnglishAndFrenchHistoryVariants() async throws {
        let environment = ProcessInfo.processInfo.environment
        let endpoint = try #require(environment["SMART_CLIPBOARD_LANGUAGE_TEST_URL"])
        let name = try #require(environment["SMART_CLIPBOARD_LANGUAGE_TEST_MODEL"])
        let profile = ConnectionProfile(provider: .omlx, model: name, endpoint: endpoint)
        _ = try OMLXAdapter().modelsRequest(profile: profile, key: "")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("language-live-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        print("Synthetic language evidence: \(root.path)")
        let suite = "LanguageLiveTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let board = NSPasteboard.withUniqueName()
        let client = ProviderClient()
        defer { defaults.removePersistentDomain(forName: suite); board.releaseGlobally(); client.session.invalidateAndCancel() }
        let model = AppModel(defaults: defaults, historyDirectory: root.appendingPathComponent("history"),
                             registerHotkeys: false, pasteboard: board, presentsWindows: false,
                             providerConversionOverride: { png, selected, format, instruction in
            try await client.convert(png: png, profile: selected, key: "", format: format, instruction: instruction)
        }, systemLanguage: { "en-GB" })
        defer { model.cancel() }
        model.connections.update(profile)
        model.connections.activeProvider = .omlx
        model.defaultFormat = .text
        let png = try fixture()
        try png.write(to: root.appendingPathComponent("spanish-source.png"))
        model.processImportedImage(png, source: "Synthetic Spanish language fixture")
        try await finish(model)
        let source = model.output
        #expect(source.localizedCaseInsensitiveContains("reunión"))
        #expect(source.localizedCaseInsensitiveContains("informe azul"))
        #expect(source.contains("582741"))
        #expect(model.resultOutputLanguage == nil)
        #expect(board.string(forType: .string) == source)
        try source.write(to: root.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)

        let entry = try #require(model.history.first)
        model.openHistory(entry, showWindow: false)
        model.outputLanguage = .system
        model.convert()
        try await finish(model)
        #expect(model.output.localizedCaseInsensitiveContains("meeting"))
        #expect(model.output.localizedCaseInsensitiveContains("blue report"))
        #expect(model.output.contains("582741"))
        #expect(model.resultOutputLanguage == "en-GB")
        try model.output.write(to: root.appendingPathComponent("english.txt"), atomically: true, encoding: .utf8)

        model.outputLanguage = .language("fr")
        model.convert()
        try await finish(model)
        #expect(model.output.localizedCaseInsensitiveContains("réunion"))
        #expect(model.output.localizedCaseInsensitiveContains("rapport bleu"))
        #expect(model.output.contains("582741"))
        try model.output.write(to: root.appendingPathComponent("french.txt"), atomically: true, encoding: .utf8)
        #expect(model.savedConversions.count == 3)
        #expect(Set(model.savedConversions.compactMap(\.outputLanguage)) == ["en-GB", "fr"])
        #expect(board.string(forType: .string) == source, "Manual translation must respect the automatic-copy preference.")
        let savedSource = try #require(model.savedConversions.first { $0.outputLanguage == nil })
        model.useSavedConversion(savedSource)
        #expect(model.output == source)
        #expect(model.outputLanguage == .source)
    }

    private func finish(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(180)
        while (model.busy || model.capturing) && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        try #require(!model.busy && !model.capturing)
        try #require(model.error == nil, "\(model.error ?? "")")
    }

    private func fixture() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1100, pixelsHigh: 320,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1100, height: 320).fill()
        ("La reunión empieza a las nueve.\nTrae el informe azul.\nCódigo: 582741" as NSString).draw(
            at: NSPoint(x: 36, y: 54),
            withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
        context.flushGraphics()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
