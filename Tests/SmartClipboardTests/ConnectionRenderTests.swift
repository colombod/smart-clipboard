import AppKit
import SwiftUI
import Testing
import ClipboardCore
@testable import SmartClipboard

/// Opt in with SMART_CLIPBOARD_RENDER_DIR. The host stays windowless throughout.
/// Appearance/layout snapshots do not establish macOS Dynamic Type, live AX, or VoiceOver behavior.
@MainActor struct ConnectionRenderTests {
    /// Run separately with --filter translatedLanguageScreens, one locale per process.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SMART_CLIPBOARD_LANGUAGE_RENDER"] != nil))
    func translatedLanguageScreens() async throws {
        let language = try #require(ProcessInfo.processInfo.environment["SMART_CLIPBOARD_LANGUAGE_RENDER"])
        let directory = try #require(ProcessInfo.processInfo.environment["SMART_CLIPBOARD_LANGUAGE_RENDER_DIR"])
        let originalArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = originalArguments
        arguments["AppleLanguages"] = [language]
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain) }
        try #require(L10n.text("Settings") == L10n.text("Settings", locale: Locale(identifier: language)))
        if language != "en" { try #require(L10n.text("Settings") != "Settings") }
        let output = URL(fileURLWithPath: directory).appendingPathComponent(language)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("language-render-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: history) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let defaults = RenderDefaults()
        let model = AppModel(defaults: defaults, historyDirectory: history, registerHotkeys: false,
                             pasteboard: board, presentsWindows: false, conversionOverride: { _, _, _, _ in
            ConversionResult(format: .markdown, content: "# Projet de démonstration\n\nUne capture, plusieurs langues.")
        })
        model.notifications = .disabled(defaults: defaults)
        model.defaultOutputLanguage = .language("fr")
        model.defaultFormat = .markdown
        model.processImportedImage(try syntheticCapturePNG(), source: "Synthetic language layout")
        let deadline = Date().addingTimeInterval(5)
        while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!model.busy && model.error == nil)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "-dark" : "-light"
            try await render(GeneralSettingsView(model: model), name: "general" + suffix,
                             scheme: scheme, size: NSSize(width: 800, height: 1300), to: output)
            try await render(CaptureView(model: model), name: "capture" + suffix,
                             scheme: scheme, size: NSSize(width: 1000, height: 850), to: output)
            try await render(CaptureView(model: model), name: "capture-minimum" + suffix,
                             scheme: scheme, size: NSSize(width: 900, height: 700), to: output)
            try await render(HistoryView(model: model), name: "history" + suffix,
                             scheme: scheme, size: NSSize(width: 640, height: 550), to: output)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SMART_CLIPBOARD_RENDER_DIR"] != nil))
    func settingsRenderWithoutWindows() async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["SMART_CLIPBOARD_RENDER_DIR"])
        #expect(!directory.isEmpty)
        guard !directory.isEmpty else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("ConnectionRenderTests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: history) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }

        for provider in AIProvider.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let defaults = RenderDefaults()
                let model = AppModel(defaults: defaults, historyDirectory: history, registerHotkeys: false, pasteboard: board, presentsWindows: false)
                model.connections.activeProvider = provider
                var profile = model.connections.activeProfile
                profile.model = provider == .codex ? "" : "example-vision-model"
                model.connections.update(profile)
                // Native tab controls do not fully draw offscreen. This captures only
                // the shell's layout; it does not verify native tabs or live scrolling.
                let host = NSHostingView(rootView: SettingsView(model: model)
                    .environment(\.colorScheme, scheme).environment(\.controlActiveState, .active))
                host.frame = NSRect(x: 0, y: 0, width: 640, height: 550)
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                await settle(host)
                #expect(host.window == nil)
                let name = provider.rawValue + (scheme == .dark ? "-dark" : "-light")
                try snapshot(host, to: output.appendingPathComponent(name + "-top.png"))
                #expect(host.window == nil)

                // Give the actual connection form sufficient height to inspect all
                // controls, independently of offscreen TabView/scroll rendering.
                let content = NSHostingView(rootView: ConnectionSettingsView(store: model.connections)
                    .padding(12).frame(width: 640, height: 1300)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme).environment(\.controlActiveState, .active))
                content.frame = NSRect(x: 0, y: 0, width: 640, height: 1300)
                content.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                await settle(content)
                #expect(content.window == nil)
                try snapshot(content, to: output.appendingPathComponent(name + "-full-content.png"))
                #expect(content.window == nil)
            }
        }
        try await renderAboutAndNotices(to: output)
        try await renderAccessibilityStates(to: output, history: history, board: board)
    }

    private func renderAboutAndNotices(to output: URL) async throws {
        let bundle: Bundle
        let noticesURL: URL
        if let path = ProcessInfo.processInfo.environment["SMART_CLIPBOARD_ABOUT_BUNDLE"] {
            try #require(!path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            bundle = try #require(Bundle(path: path))
            // Fail instead of silently rendering development metadata or a fallback icon.
            let version = try #require(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            let build = try #require(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            try #require(!version.isEmpty && !build.isEmpty)
            let iconURL = try #require(bundle.url(forResource: "AppIcon", withExtension: "icns"))
            _ = try #require(NSImage(contentsOf: iconURL))
            noticesURL = try #require(bundle.url(forResource: "ThirdPartyNotices", withExtension: "txt"))
        } else {
            bundle = .main
            // The test executable has no app resources; use the real source notices for this render.
            noticesURL = bundle.url(forResource: "ThirdPartyNotices", withExtension: "txt")
                ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().appendingPathComponent("Resources/ThirdPartyNotices.txt")
        }
        let notices = try String(contentsOf: noticesURL, encoding: .utf8)
        try #require(!notices.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        for scheme in [ColorScheme.light, .dark] {
            let panels = [
                ("about", AnyView(AboutView(bundle: bundle).frame(width: 616, height: 480).clipped())),
                ("third-party-notices", AnyView(ThirdPartyNoticesView(text: notices).frame(width: 580, height: 440).clipped()))
            ]
            for (name, panel) in panels {
                // Keep the actual tab/sheet dimensions inside the settings-sized canvas so
                // content that does not fit is visible in the snapshot as clipping.
                let host = NSHostingView(rootView: panel.frame(width: 640, height: 550)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme).environment(\.controlActiveState, .active))
                host.frame = NSRect(x: 0, y: 0, width: 640, height: 550)
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                await settle(host)
                #expect(host.window == nil)
                try snapshot(host, to: output.appendingPathComponent(name + (scheme == .dark ? "-dark.png" : "-light.png")))
                #expect(host.window == nil)
            }
            try await render(AboutView(bundle: bundle).frame(width: 616, height: 480).clipped(),
                             name: "about-high-contrast" + (scheme == .dark ? "-dark" : "-light"),
                             scheme: scheme, increasedContrast: true, size: NSSize(width: 640, height: 550), to: output)
        }
    }

    private func renderAccessibilityStates(to output: URL, history: URL, board: NSPasteboard) async throws {
        var conversions = 0
        let capture = CaptureClient(hasAccess: { false }, requestAccess: { false }, takeImage: { _ in
            throw ClipError.message("Synthetic render tests must never capture the screen.")
        })
        let model = AppModel(defaults: RenderDefaults(), historyDirectory: history.appendingPathComponent("synthetic-accessibility"),
                             registerHotkeys: false, captureClient: capture, pasteboard: board, presentsWindows: false,
                             conversionOverride: { _, _, _, _ in
            conversions += 1
            return ConversionResult(format: .markdown, content: "# Synthetic render fixture\n\n| Item | Quantity |\n| --- | --- |\n| Juniper | 27 |\n| Quartz | 64 |")
        })
        defer { model.cancel() }
        model.settingsTab = "general"
        for scheme in [ColorScheme.light, .dark] {
            // The selected General tab remains shell-only offscreen. This does not
            // establish native tab drawing, scrolling, keyboard navigation, or AX behavior.
            try await render(SettingsView(model: model),
                             name: "settings-general-shell-high-contrast" + (scheme == .dark ? "-dark" : "-light"),
                             scheme: scheme, increasedContrast: true, size: NSSize(width: 640, height: 550), to: output)
        }
        try await render(SettingsView(model: model), name: "settings-general-shell-expanded-light", scheme: .light,
                         size: NSSize(width: 900, height: 850), to: output)
        try await render(CaptureView(model: model), name: "capture-empty-high-contrast-light", scheme: .light,
                         increasedContrast: true, size: NSSize(width: 1000, height: 700), to: output)

        let png = try syntheticCapturePNG()
        model.defaultFormat = .markdown
        model.processImportedImage(png, source: "Synthetic accessibility render fixture")
        let deadline = Date().addingTimeInterval(5)
        while (model.busy || model.capturing) && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!model.busy && !model.capturing)
        try #require(model.error == nil)
        try #require(model.history.count == 1 && conversions == 1)
        try #require(board.string(forType: .string) == model.output)
        try await render(CaptureView(model: model), name: "capture-result-high-contrast-dark", scheme: .dark,
                         increasedContrast: true, size: NSSize(width: 1000, height: 700), to: output)
        for scheme in [ColorScheme.light, .dark] {
            try await render(HistoryView(model: model),
                             name: "history-synthetic-high-contrast" + (scheme == .dark ? "-dark" : "-light"),
                             scheme: scheme, increasedContrast: true, size: NSSize(width: 640, height: 550), to: output)
        }
        #expect(conversions == 1)
    }

    private func syntheticCapturePNG() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 780, pixelsHigh: 280,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 780, height: 280).fill()
        ("Synthetic render fixture\nItem        Quantity\nJuniper     27\nQuartz      64" as NSString)
            .draw(at: NSPoint(x: 32, y: 38), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 30, weight: .medium), .foregroundColor: NSColor.black
            ])
        context.flushGraphics()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func render<Content: View>(_ content: Content, name: String, scheme: ColorScheme,
                                       increasedContrast: Bool = false, size: NSSize, to output: URL) async throws {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.controlActiveState, .active))
        host.frame = NSRect(origin: .zero, size: size)
        let appearance: NSAppearance.Name = increasedContrast
            ? (scheme == .dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (scheme == .dark ? .darkAqua : .aqua)
        // Let the host supply both scheme and contrast. Overriding colorScheme
        // separately can resolve dynamic NSColors with the standard appearance.
        host.appearance = NSAppearance(named: appearance)
        await settle(host)
        #expect(host.window == nil)
        #expect(host.bounds.size == size)
        try snapshot(host, to: output.appendingPathComponent(name + ".png"))
        #expect(host.window == nil)
    }

    private func settle(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        // Allow SwiftUI's queued layout work to reach the otherwise unattached host.
        try? await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    private func snapshot(_ host: NSView, to url: URL) throws {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        #expect(bitmap.pixelsWide >= 640)
        #expect(bitmap.pixelsHigh >= 550)

        var shades = Set<UInt32>()
        var visible = 0
        var minimum = CGFloat(1), maximum = CGFloat(0)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.05 else { continue }
                visible += 1
                let red = UInt32(max(0, min(255, Int(color.redComponent * 255))))
                let green = UInt32(max(0, min(255, Int(color.greenComponent * 255))))
                let blue = UInt32(max(0, min(255, Int(color.blueComponent * 255))))
                shades.insert((red << 16) | (green << 8) | blue)
                let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
            }
        }
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
        #expect(visible > 200, "Render is mostly transparent: \(url.lastPathComponent)")
        #expect(shades.count >= 16, "Render is blank or uniform: \(url.lastPathComponent)")
        #expect(maximum - minimum > 0.2, "Render contains no meaningful foreground detail: \(url.lastPathComponent)")
    }

}

/// Keeps every settings read and write in memory, including first-run migration.
private final class RenderDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
    override func integer(forKey defaultName: String) -> Int { values[defaultName] as? Int ?? 0 }
}
