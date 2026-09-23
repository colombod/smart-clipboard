import AppKit
import SwiftUI
import Testing
import ClipboardCore
@testable import SmartClipboard

/// Documentation images use real views with sample state, never the running app.
/// Opt in with SMART_CLIPBOARD_DOC_SCREENSHOTS pointing to an output directory.
@MainActor struct DocumentationScreenshotTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SMART_CLIPBOARD_DOC_SCREENSHOTS"] != nil))
    func renderSampleWalkthroughWithoutWindows() async throws {
        // This volatile argument domain affects this test process only.
        let originalArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = originalArguments
        arguments["AppleLanguages"] = ["en"]
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain) }
        try #require(L10n.text("Settings") == "Settings")
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SMART_CLIPBOARD_DOC_SCREENSHOTS"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("documentation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let originalBoardCount = board.changeCount
        let originalWindows = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let defaults = DocumentationDefaults()
        let backend = DocumentationHotKeys()
        let hotkeys = HotKeyManager(backend: backend, systemShortcuts: { [] })
        try hotkeys.register(.region, id: 1)
        try hotkeys.register(.window, id: 2)
        defer { hotkeys.unregisterAll() }
        var captureCalls = 0
        let capture = CaptureClient(hasAccess: { true }, requestAccess: {
            Issue.record("Documentation must never request Screen Recording access."); return false
        }, takeImage: { _ in
            captureCalls += 1
            throw ClipError.message("Documentation must never capture the screen.")
        })

        let samplePNG = try sampleNotePNG()
        let store = try HistoryStore(directory: directory)
        let project = try #require(try store.add(png: samplePNG, source: "Project note"))
        let french = "Note de projet\n\nPréparer le lancement\n• Relire le texte de la page d’accueil\n• Partager l’aperçu avec l’équipe"
        let markdown = "# Project note\n\n## Launch checklist\n\n- Review the homepage copy\n- Share the preview with the team\n- Gather feedback by Friday"
        let plain = "Project note\n\nLaunch checklist\nReview the homepage copy\nShare the preview with the team\nGather feedback by Friday"
        try store.save(SavedConversion(format: .text, content: french, instruction: "", outputLanguage: "fr"), for: project.id)
        try store.save(SavedConversion(format: .markdown, content: markdown, instruction: ""), for: project.id)
        try store.save(SavedConversion(format: .text, content: plain, instruction: ""), for: project.id)
        let ideas = try #require(try store.add(png: try sampleNotePNG(title: "Ideas for next week", lines: ["Write the first draft", "Make a simple prototype", "Ask for feedback"]), source: "Ideas for next week"))
        try store.save(SavedConversion(format: .text, content: "Ideas for next week\nWrite the first draft\nMake a simple prototype\nAsk for feedback", instruction: "", method: .appleVision), for: ideas.id)
        // Use a fixed, fictional date so rerunning the screenshots is predictable.
        let index = directory.appendingPathComponent("index.json")
        var saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [[String: Any]])
        for position in saved.indices { saved[position]["createdAt"] = 811_331_520.0 - Double(position * 3600) }
        try JSONSerialization.data(withJSONObject: saved, options: [.sortedKeys]).write(to: index, options: .atomic)

        let model = AppModel(defaults: defaults, historyDirectory: directory, registerHotkeys: false,
                             hotkeyManager: hotkeys, captureClient: capture, pasteboard: board, presentsWindows: false,
                             conversionOverride: { _, _, _, _ in
            Issue.record("Documentation must never invoke a conversion.")
            throw ClipError.message("Unexpected documentation conversion")
        }, providerConversionOverride: { _, _, _, _ in
            Issue.record("Documentation must never invoke a provider.")
            throw ClipError.message("Unexpected documentation provider request")
        }, traceOverride: { _, _ in
            Issue.record("Documentation must never invoke the trace helper.")
            throw ClipError.message("Unexpected documentation trace")
        }, systemLanguage: { "en" })
        defer { model.cancel() }
        model.refreshReadiness()
        model.defaultFormat = .auto
        model.defaultOutputLanguage = .source
        model.copyAutomatically = true
        model.connections.activeProvider = .omlx
        var profile = model.connections.activeProfile
        profile.endpoint = "http://127.0.0.1:8999/v1"
        profile.model = "mlx-community/Qwen3-VL-8B-Instruct-4bit"
        model.connections.update(profile)
        try #require(model.connections.testSuccess == nil)
        try #require(model.captureReady && model.error == nil)

        var images: [[String: Any]] = []
        images.append(try await render(GeneralSettingsView(model: model), name: "capture-settings.png",
                                       size: NSSize(width: 800, height: 575), to: output,
                                       view: "GeneralSettingsView", sample: "Auto detect; Keep source language; top portion of General settings."))
        images.append(try await render(ConnectionSettingsView(store: model.connections), name: "local-connection.png",
                                       size: NSSize(width: 800, height: 685), to: output,
                                       view: "ConnectionSettingsView", sample: "Example localhost oMLX endpoint and 8B model; connection is explicitly unverified."))
        model.defaultFormat = .svg
        model.defaultSVGMethod = .trace
        model.defaultTraceSettings = TraceSettings(preset: .photo, detail: .balanced)
        images.append(try await render(GeneralSettingsView(model: model), name: "svg-tracing.png",
                                       size: NSSize(width: 800, height: 670), to: output,
                                       view: "GeneralSettingsView", sample: "SVG; Trace on device; Photo; Balanced; top portion of General settings."))
        images.append(try await render(HistoryView(model: model), name: "history.png",
                                       size: NSSize(width: 860, height: 330), to: output,
                                       view: "HistoryView", sample: "Two fictional notes, including source text, Markdown and French saved variants; fixed fictional dates."))
        model.defaultFormat = .auto
        model.openHistory(try #require(model.history.first(where: { $0.id == project.id })), showWindow: false)
        model.useSavedConversion(try #require(model.savedConversions.first(where: { $0.format == .markdown })))
        images.append(try await render(CaptureView(model: model), name: "result.png",
                                       size: NSSize(width: 1000, height: 740), to: output,
                                       view: "CaptureView", sample: "Fictional Project note original and saved Markdown; manually authored sample output, no AI inference."))

        try #require(captureCalls == 0 && !model.busy && !model.capturing && model.error == nil)
        #expect(board.changeCount == originalBoardCount)
        for window in NSApplication.shared.windows where !originalWindows.contains(ObjectIdentifier(window)) {
            // Native text controls may allocate an invisible internal TUINSWindow.
            // No document host is attached to it and it must never be presented.
            #expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow)
        }
        #expect(model.connections.testSuccess == nil)
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let appInfo = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: sourceRoot.appendingPathComponent("Resources/Info.plist")), format: nil) as? [String: Any])
        let manifest: [String: Any] = [
            "schema": 1,
            "sourceVersion": appInfo["CFBundleShortVersionString"] as? String ?? "unknown",
            "sourceBuild": appInfo["CFBundleVersion"] as? String ?? "unknown",
            "provenance": "Offscreen renders of actual repository SwiftUI/AppKit views. Sample settings and fictional notes only. These are documentation illustrations, not screenshots of a user session or native UAT evidence.",
            "rendering": "English, light appearance, unattached NSHostingView, native view-sized PNG capture. No fabricated window chrome and no bitmap cropping or editing. AppKit may allocate an invisible internal TUINSWindow for controls; all rendered hosts remain windowless and no window is presented.",
            "isolation": "In-memory defaults, temporary history, private pasteboard, fake hotkey backend and capture client, no presented windows, no global shortcuts, no screen capture, no credentials, no network or AI calls. Editor readiness is simulated.",
            "reproduce": "SMART_CLIPBOARD_DOC_SCREENSHOTS=\"$PWD/docs/images\" swift test --filter DocumentationScreenshotTests",
            "images": images
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: output.appendingPathComponent("screenshots.json"), options: .atomic)
    }

    private func sampleNotePNG(title: String = "Project note", lines: [String] = ["Launch checklist", "Review the homepage copy", "Share the preview with the team", "Gather feedback by Friday"]) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 700, pixelsHigh: 265,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 700, height: 265).fill()
        (title as NSString).draw(at: NSPoint(x: 30, y: 210), withAttributes: [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor.black
        ])
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 30, y: 161 - index * 37), withAttributes: [
                .font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.darkGray
            ])
        }
        context.flushGraphics()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func render<Content: View>(_ content: Content, name: String, size: NSSize, to output: URL,
                                       view: String, sample: String) async throws -> [String: Any] {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.locale, Locale(identifier: "en_GB"))
            .environment(\.controlActiveState, .active))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        try #require(host.window == nil)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try #require(png.count > 10_000, "Documentation image should contain visible UI content.")
        try png.write(to: output.appendingPathComponent(name), options: .atomic)
        #expect(host.window == nil)
        return ["file": name, "view": view, "sample": sample, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh]
    }
}

private final class DocumentationDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
    override func integer(forKey defaultName: String) -> Int { values[defaultName] as? Int ?? 0 }
}

@MainActor private final class DocumentationHotKeys: HotKeyBackend {
    var handler: ((UInt32) -> Void)?
    func register(_ shortcut: Shortcut, id: UInt32) throws { /* In-memory test registration only. */ }
    func unregister(_ id: UInt32) {}
}
