import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import ClipboardCore

@MainActor final class AppModel: ObservableObject {
    @Published var png: Data?
    @Published var output = ""
    @Published var resultFormat: OutputFormat = .text
    @Published var format: OutputFormat = .auto
    @Published var instruction = ""
    @Published var busy = false
    @Published var capturing = false
    @Published var error: String?
    @Published var notice = ""
    @Published var provider: String { didSet { defaults.set(provider, forKey: "provider") } }
    @Published var apiModel: String { didSet { defaults.set(apiModel, forKey: "apiModel") } }
    @Published var codexModel: String { didSet { defaults.set(codexModel, forKey: "codexModel") } }
    @Published var codexExecutable: String { didSet { defaults.set(codexExecutable, forKey: "codexExecutable") } }
    @Published var defaultFormat: OutputFormat { didSet { defaults.set(defaultFormat.rawValue, forKey: "defaultFormat") } }
    @Published var copyAutomatically: Bool { didSet { defaults.set(copyAutomatically, forKey: "copyAutomatically") } }
    @Published var regionShortcut: Shortcut
    @Published var windowShortcut: Shortcut
    let hotkeys = HotKeyManager()
    private let defaults = UserDefaults.standard
    private var task: Task<Void, Never>?
    private var panel: NSWindow?
    private var settings: NSWindow?

    init() {
        provider = UserDefaults.standard.string(forKey: "provider") ?? "api"
        apiModel = UserDefaults.standard.string(forKey: "apiModel") ?? "gpt-5.6-luna"
        codexModel = UserDefaults.standard.string(forKey: "codexModel") ?? ""
        codexExecutable = UserDefaults.standard.string(forKey: "codexExecutable") ?? ""
        defaultFormat = OutputFormat(rawValue: UserDefaults.standard.string(forKey: "defaultFormat") ?? "") ?? .auto
        copyAutomatically = UserDefaults.standard.bool(forKey: "copyAutomatically")
        regionShortcut = Self.loadShortcut("regionShortcut") ?? .region
        windowShortcut = Self.loadShortcut("windowShortcut") ?? .window
        hotkeys.handler = { [weak self] id in self?.capture(window: id == 2) }
        do { try hotkeys.register(regionShortcut, id: 1); try hotkeys.register(windowShortcut, id: 2) }
        catch { self.error = error.localizedDescription }
    }
    static func loadShortcut(_ key: String) -> Shortcut? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }
    func setShortcut(_ shortcut: Shortcut, window: Bool) throws {
        let old = window ? windowShortcut : regionShortcut
        let other = window ? regionShortcut : windowShortcut
        guard shortcut.key != other.key || shortcut.modifiers != other.modifiers else { throw ClipError.message("Use different shortcuts for region and window capture.") }
        do { try hotkeys.register(shortcut, id: window ? 2 : 1) }
        catch { try? hotkeys.register(old, id: window ? 2 : 1); throw error }
        if window { windowShortcut = shortcut } else { regionShortcut = shortcut }
        defaults.set(try JSONEncoder().encode(shortcut), forKey: window ? "windowShortcut" : "regionShortcut")
    }
    func showPanel() {
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Smart Clipboard"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 850, height: 590)
            window.contentView = NSHostingView(rootView: CaptureView(model: self))
            window.center(); panel = window
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
    func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Smart Clipboard Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func capture(window: Bool = false) {
        guard !capturing, !busy else { return }
        capturing = true; error = nil; notice = ""
        panel?.orderOut(nil); settings?.orderOut(nil)
        task = Task {
            defer { capturing = false; task = nil }
            do {
                try await Task.sleep(for: .milliseconds(250))
                if let data = try await CaptureService.capture(window: window) {
                    png = data; output = ""; instruction = ""; format = defaultFormat
                    showPanel()
                }
            } catch is CancellationError {} catch { self.error = error.localizedDescription; showPanel() }
        }
    }
    func importImage() {
        guard !busy, !capturing else { return }
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.png, .jpeg, .tiff, .heic]; picker.canChooseDirectories = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let bitmap = NSBitmapImageRep(data: data), let normalized = bitmap.representation(using: .png, properties: [:]) else { throw ClipError.message("Could not read this image.") }
            png = normalized; output = ""; error = nil; notice = ""; format = defaultFormat; instruction = ""
            showPanel()
        } catch { self.error = error.localizedDescription }
    }
    func convert(local: Bool = false) {
        guard let png, !busy else { return }
        if format == .image && !local { copyImage(); return }
        let requested = format, extra = instruction, connection = provider, model = apiModel, cliModel = codexModel, executable = codexExecutable
        busy = true; error = nil; notice = ""; output = ""
        task = Task {
            defer { busy = false; task = nil }
            do {
                let result: ConversionResult
                if local { result = ConversionResult(format: .text, content: try await CaptureService.recognize(png)) }
                else if connection == "codex" { result = try await AIService.codex(png: png, executable: executable, model: cliModel, format: requested, instruction: extra) }
                else { result = try await AIService.api(png: png, key: KeyStore.read(), model: model, format: requested, instruction: extra) }
                try Task.checkCancellation()
                resultFormat = result.format; output = result.content
                if copyAutomatically { copyOutput() }
            } catch is CancellationError { notice = "Conversion cancelled." }
            catch { if Task.isCancelled { notice = "Conversion cancelled." } else { self.error = error.localizedDescription } }
        }
    }
    func cancel() { task?.cancel() }
    func clear() { guard !busy else { return }; png = nil; output = ""; instruction = ""; error = nil; notice = "" }
    func copyImage() {
        guard let png else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        notice = "Image copied."
    }
    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        // Keep generated markup inert; don't put unreviewed HTML on the rich-text pasteboard.
        NSPasteboard.general.setString(output, forType: .string)
        notice = "\(resultFormat.title) copied."
    }
    func save(image: Bool = false) {
        guard image ? png != nil : !output.isEmpty else { return }
        let ext = image ? "png" : resultFormat.fileExtension
        let dialog = NSSavePanel(); dialog.nameFieldStringValue = "Clip.\(ext)"
        dialog.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        do {
            if image { try png?.write(to: url, options: .atomic) } else { try output.write(to: url, atomically: true, encoding: .utf8) }
            notice = "Saved \(url.lastPathComponent)."
        } catch { self.error = error.localizedDescription }
    }
    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
