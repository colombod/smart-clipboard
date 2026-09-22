import AppKit
import SwiftUI
import Testing
import ClipboardCore
@testable import SmartClipboard

/// Opt in with SMART_CLIPBOARD_RENDER_DIR. The host stays windowless throughout.
@MainActor struct ConnectionRenderTests {
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
        }
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
