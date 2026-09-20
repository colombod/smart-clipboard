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
    @Published var settingsTab = "connection"
    @Published var provider: String { didSet { defaults.set(provider, forKey: "provider") } }
    @Published var apiModel: String { didSet { defaults.set(apiModel, forKey: "apiModel") } }
    @Published var codexModel: String { didSet { defaults.set(codexModel, forKey: "codexModel") } }
    @Published var codexExecutable: String { didSet { defaults.set(codexExecutable, forKey: "codexExecutable") } }
    @Published var defaultFormat: OutputFormat { didSet { defaults.set(defaultFormat.rawValue, forKey: "defaultFormat") } }
    @Published var copyAutomatically: Bool { didSet { defaults.set(copyAutomatically, forKey: "copyAutomatically") } }
    @Published var regionShortcut: Shortcut
    @Published var windowShortcut: Shortcut
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var historyLimit: Int
    @Published private(set) var historyBytes: Int64 = 0
    @Published private(set) var activeHistoryID: UUID?
    private var resultInstruction = ""
    private var historyStore: HistoryStore?
    private var historyWindow: NSWindow?
    let hotkeys = HotKeyManager()
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var panel: NSWindow?
    private var settings: NSWindow?

    init(defaults: UserDefaults = .standard, historyDirectory: URL? = nil, registerHotkeys: Bool = true) {
        self.defaults = defaults
        historyLimit = defaults.object(forKey: "historyLimit") == nil ? HistoryStore.defaultLimit : min(max(0, defaults.integer(forKey: "historyLimit")), HistoryStore.maximumLimit)
        provider = defaults.string(forKey: "provider") ?? "api"
        apiModel = defaults.string(forKey: "apiModel") ?? "gpt-5.6-luna"
        codexModel = defaults.string(forKey: "codexModel") ?? ""
        codexExecutable = defaults.string(forKey: "codexExecutable") ?? ""
        defaultFormat = OutputFormat(rawValue: defaults.string(forKey: "defaultFormat") ?? "") ?? .auto
        copyAutomatically = defaults.bool(forKey: "copyAutomatically")
        regionShortcut = Self.loadShortcut("regionShortcut", defaults: defaults) ?? .region
        windowShortcut = Self.loadShortcut("windowShortcut", defaults: defaults) ?? .window
        hotkeys.handler = { [weak self] id in self?.capture(window: id == 2) }
        if registerHotkeys {
            do { try hotkeys.register(regionShortcut, id: 1); try hotkeys.register(windowShortcut, id: 2) }
            catch { self.error = error.localizedDescription }
        }
        do {
            let directory = historyDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Smart Clipboard/History", isDirectory: true)
            historyStore = try HistoryStore(directory: directory, limit: historyLimit)
            refreshHistory()
        } catch { self.error = "Could not open capture history: " + error.localizedDescription }
    }
    static func loadShortcut(_ key: String, defaults: UserDefaults) -> Shortcut? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
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
    func showSettings(tab: String? = nil) {
        if let tab { settingsTab = tab }
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
        persistCurrentOutput()
        panel?.orderOut(nil); settings?.orderOut(nil); historyWindow?.orderOut(nil)
        task = Task {
            defer { capturing = false; task = nil }
            do {
                try await Task.sleep(for: .milliseconds(250))
                if let data = try await CaptureService.capture(window: window) {
                    acceptCapture(data, source: window ? "Window capture" : "Region capture")
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
            acceptCapture(normalized, source: url.lastPathComponent)
            showPanel()
        } catch { self.error = error.localizedDescription }
    }
    func convert(local: Bool = false) {
        guard let png, !busy else { return }
        if format == .image && !local { copyImage(); return }
        let requested = format, extra = instruction, connection = provider, model = apiModel, cliModel = codexModel, executable = codexExecutable
        persistCurrentOutput()
        busy = true; error = nil; notice = ""; output = ""
        task = Task {
            defer { busy = false; task = nil }
            do {
                let result: ConversionResult
                if local { result = ConversionResult(format: .text, content: try await CaptureService.recognize(png)) }
                else if connection == "codex" { result = try await AIService.codex(png: png, executable: executable, model: cliModel, format: requested, instruction: extra) }
                else { result = try await AIService.api(png: png, key: KeyStore.read(), model: model, format: requested, instruction: extra) }
                try Task.checkCancellation()
                resultFormat = result.format; output = result.content; resultInstruction = extra
                persistCurrentOutput()
                if copyAutomatically { copyOutput() }
            } catch is CancellationError { notice = "Conversion cancelled." }
            catch { if Task.isCancelled { notice = "Conversion cancelled." } else { self.error = error.localizedDescription } }
        }
    }
    func cancel() { task?.cancel() }
    func clear() { guard !busy else { return }; persistCurrentOutput(); resetCurrent() }
    private func resetCurrent() { activeHistoryID = nil; png = nil; output = ""; instruction = ""; notice = "" }
    func acceptCapture(_ data: Data, source: String) {
        persistCurrentOutput()
        png = data; output = ""; instruction = ""; format = defaultFormat; error = nil; notice = ""; activeHistoryID = nil
        do {
            guard let historyStore else { throw ClipError.message("History storage is unavailable. Check the local history folder before saving more clips.") }
            activeHistoryID = try historyStore.add(png: data, source: source)?.id
        }
        catch { self.error = "Capture opened, but could not save history: " + error.localizedDescription }
        refreshHistory()
    }
    private func refreshHistory() {
        history = historyStore?.entries ?? []
        historyBytes = historyStore?.diskBytes ?? 0
        if let id = activeHistoryID, !history.contains(where: { $0.id == id }) { activeHistoryID = nil }
    }
    func persistCurrentOutput() {
        guard let id = activeHistoryID, !output.isEmpty else { return }
        let existing = history.first(where: { $0.id == id })?.conversions.last(where: { $0.format == resultFormat })
        guard existing?.content != output || existing?.instruction != resultInstruction else { return }
        do { try historyStore?.save(SavedConversion(format: resultFormat, content: output, instruction: resultInstruction), for: id) }
        catch { self.error = "Could not save the result in history: " + error.localizedDescription }
        refreshHistory()
    }
    func openHistory(_ entry: HistoryEntry, showWindow: Bool = true) {
        guard !busy, !capturing else { return }
        persistCurrentOutput()
        do {
            guard let historyStore else { return }
            let data = try historyStore.image(for: entry.id)
            let current = historyStore.entries.first(where: { $0.id == entry.id }) ?? entry
            activeHistoryID = current.id; png = data; output = ""; instruction = ""; format = defaultFormat; error = nil
            if let result = current.conversions.last { resultFormat = result.format; output = result.content; instruction = result.instruction; resultInstruction = result.instruction }
            notice = "Opened saved capture. Choose any format to convert the original again."
            if showWindow { showPanel() }
        } catch { self.error = error.localizedDescription }
    }
    var savedConversions: [SavedConversion] { history.first(where: { $0.id == activeHistoryID })?.conversions ?? [] }
    func useSavedConversion(_ result: SavedConversion) {
        guard !busy else { return }
        persistCurrentOutput()
        resultFormat = result.format; output = result.content; instruction = result.instruction; resultInstruction = result.instruction; format = result.format
        notice = "Loaded saved \(result.format.title)."
    }
    func historyImageURL(_ entry: HistoryEntry) -> URL? { historyStore?.imageURL(for: entry.id) }
    func setHistoryLimit(_ value: Int) {
        guard !busy, !capturing else { return }
        persistCurrentOutput()
        do {
            guard let historyStore else { throw ClipError.message("History storage is unavailable.") }
            try historyStore.setLimit(value)
            historyLimit = historyStore.limit; defaults.set(historyLimit, forKey: "historyLimit")
            if historyLimit == 0 { resetCurrent() }
        } catch { self.error = error.localizedDescription }
        refreshHistory()
    }
    func deleteHistory(_ entry: HistoryEntry) {
        guard !busy, !capturing else { return }
        do {
            guard let historyStore else { throw ClipError.message("History storage is unavailable; no files were deleted.") }
            try historyStore.remove(entry.id)
            if activeHistoryID == entry.id { resetCurrent() }
        } catch { self.error = error.localizedDescription }
        refreshHistory()
    }
    func clearHistory() {
        guard !busy, !capturing else { return }
        do {
            guard let historyStore else { throw ClipError.message("History storage is unavailable; no files were deleted.") }
            try historyStore.clear(); resetCurrent(); notice = "History cleared."
        }
        catch { self.error = error.localizedDescription }
        refreshHistory()
    }
    func showHistory() {
        persistCurrentOutput()
        if historyWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 550), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Capture History"; window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 540, height: 380)
            window.contentView = NSHostingView(rootView: HistoryView(model: self))
            window.center(); historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); historyWindow?.makeKeyAndOrderFront(nil)
    }
    func copyImage() {
        guard let png else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        notice = "Image copied."
    }
    func copyOutput() {
        persistCurrentOutput()
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        // Keep generated markup inert; don't put unreviewed HTML on the rich-text pasteboard.
        NSPasteboard.general.setString(output, forType: .string)
        notice = "\(resultFormat.title) copied."
    }
    func save(image: Bool = false) {
        persistCurrentOutput()
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
