import AppKit
import Carbon
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
    @Published private(set) var choosingFile = false
    @Published var error: String?
    @Published var notice = ""
    @Published var settingsTab = "connection"
    let connections: ConnectionStore
    // Supplied only by the production app lifecycle, never by tests or audit builds.
    var updates: UpdateController?
    @Published var defaultFormat: OutputFormat { didSet { defaults.set(defaultFormat.rawValue, forKey: "defaultFormat") } }
    @Published var defaultInstruction: String { didSet { defaults.set(defaultInstruction, forKey: "defaultInstruction") } }
    @Published var copyAutomatically: Bool { didSet { defaults.set(copyAutomatically, forKey: "copyAutomatically") } }
    @Published var regionShortcut: Shortcut
    @Published var windowShortcut: Shortcut
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var historyLimit: Int
    @Published private(set) var historyBytes: Int64 = 0
    @Published private(set) var activeHistoryID: UUID?
    private var resultInstruction = ""
    private var resultProvenance: ConversionProvenance?
    private var uneditedOutput = ""
    var resultOrigin: String? {
        guard let provenance = resultProvenance else { return nil }
        let provider = AIProvider(rawValue: provenance.providerID)?.title ?? "On-device text extraction"
        let model = provenance.effectiveModel ?? (provenance.requestedModel.isEmpty ? "Default model" : provenance.requestedModel)
        return provider + (provenance.providerID == "apple-vision" ? "" : " · " + model) + (provenance.userEdited ? " · Edited" : "")
    }
    private var historyStore: HistoryStore?
    private var historyWindow: NSWindow?
    @Published var menuBarInstalled = false
    @Published private(set) var screenAccess = false
    @Published private(set) var shortcutProblems: [UInt32: String] = [:]
    @Published private(set) var shortcutsPaused = false
    @Published private(set) var lastShortcutEvent = "No shortcut received yet"
    private let pasteboard: NSPasteboard
    private let presentsWindows: Bool
    private let conversionOverride: ((Data, OutputFormat, String, Bool) async throws -> ConversionResult)?
    private let providerConversionOverride: ((Data, ConnectionProfile, OutputFormat, String) async throws -> ProviderConversion)?
    private let captureClient: CaptureClient
    private let registersHotkeys: Bool
    let hotkeys: HotKeyManager
    var captureReady: Bool { screenAccess && !shortcutsPaused && shortcutProblems.isEmpty && hotkeys.isRegistered(1) && hotkeys.isRegistered(2) }
    func shortcutStatus(_ id: UInt32) -> String {
        if shortcutsPaused { return "Paused while recording a shortcut" }
        if let problem = shortcutProblems[id] { return problem }
        return hotkeys.isRegistered(id) ? "Registered and listening" : "Not registered"
    }
    func refreshReadiness() {
        screenAccess = captureClient.hasAccess()
        if registersHotkeys && !shortcutsPaused { registerShortcuts() }
    }
    private func registerShortcuts() {
        // Try each independently: a region conflict must not disable the window shortcut.
        for (id, shortcut) in [(UInt32(1), regionShortcut), (UInt32(2), windowShortcut)] {
            do { try hotkeys.register(shortcut, id: id); shortcutProblems[id] = nil }
            catch { shortcutProblems[id] = error.localizedDescription }
        }
    }
    func pauseShortcuts() { shortcutsPaused = true; hotkeys.unregisterAll() }
    func resumeShortcuts() { shortcutsPaused = false; if registersHotkeys { registerShortcuts() } }
    func requestScreenAccess() {
        #if ACCESSIBILITY_AUDIT
        error = "Accessibility audit: requesting macOS Screen Recording permission was not performed."
        #else
        _ = captureClient.requestAccess(); refreshReadiness()
        #endif
    }
    func openScreenAccessSettings() {
        #if ACCESSIBILITY_AUDIT
        error = "Accessibility audit: opening macOS Screen Recording settings was not performed."
        #else
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        #endif
    }

    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var panel: NSWindow?
    private var settings: NSWindow?

    init(defaults: UserDefaults = .standard, historyDirectory: URL? = nil, registerHotkeys: Bool = true, hotkeyManager: HotKeyManager? = nil, captureClient: CaptureClient? = nil, pasteboard: NSPasteboard? = nil, presentsWindows: Bool = true, conversionOverride: ((Data, OutputFormat, String, Bool) async throws -> ConversionResult)? = nil, providerConversionOverride: ((Data, ConnectionProfile, OutputFormat, String) async throws -> ProviderConversion)? = nil) {
        self.pasteboard = pasteboard ?? .general
        self.presentsWindows = presentsWindows
        self.conversionOverride = conversionOverride
        self.providerConversionOverride = providerConversionOverride
        self.captureClient = captureClient ?? CaptureClient()
        self.hotkeys = hotkeyManager ?? HotKeyManager()
        self.registersHotkeys = registerHotkeys
        self.defaults = defaults
        self.connections = ConnectionStore(defaults: defaults)
        historyLimit = defaults.object(forKey: "historyLimit") == nil ? HistoryStore.defaultLimit : min(max(0, defaults.integer(forKey: "historyLimit")), HistoryStore.maximumLimit)
        defaultFormat = OutputFormat(rawValue: defaults.string(forKey: "defaultFormat") ?? "") ?? .auto
        defaultInstruction = defaults.string(forKey: "defaultInstruction") ?? ""
        copyAutomatically = defaults.bool(forKey: "copyAutomatically")
        regionShortcut = Self.loadShortcut("regionShortcut", defaults: defaults) ?? .region
        windowShortcut = Self.loadShortcut("windowShortcut", defaults: defaults) ?? .window
        hotkeys.handler = { [weak self] id in
            guard let self else { return }
            self.lastShortcutEvent = "\(id == 2 ? "Window" : "Region") shortcut received at \(Date().formatted(date: .omitted, time: .standard))"
            self.capture(window: id == 2)
        }
        if registerHotkeys { refreshReadiness() }
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
        let other = window ? regionShortcut : windowShortcut
        guard shortcut.key != other.key || shortcut.modifiers != other.modifiers else { throw ClipError.message("Use different shortcuts for region and window capture.") }
        try hotkeys.register(shortcut, id: window ? 2 : 1)
        shortcutProblems[window ? 2 : 1] = nil
        if window { windowShortcut = shortcut } else { regionShortcut = shortcut }
        defaults.set(try JSONEncoder().encode(shortcut), forKey: window ? "windowShortcut" : "regionShortcut")
    }
    func findAvailableShortcuts() {
        for id: UInt32 in [1, 2] where shortcutProblems[id] != nil || !hotkeys.isRegistered(id) {
            let key = id == 1 ? Shortcut.region.key : Shortcut.window.key
            let digit = id == 1 ? "3" : "4"
            let options: [(UInt32, String)] = [
                (UInt32(cmdKey | shiftKey | optionKey), "⌥⇧⌘"),
                (UInt32(cmdKey | controlKey | shiftKey), "⌃⇧⌘"),
                (UInt32(cmdKey | optionKey), "⌥⌘"),
                (UInt32(controlKey | shiftKey), "⌃⇧")
            ]
            for (modifiers, label) in options {
                do { try setShortcut(Shortcut(key: key, modifiers: modifiers, label: label + digit), window: id == 2); break }
                catch { shortcutProblems[id] = error.localizedDescription }
            }
        }
    }
    func showPanel() {
        guard presentsWindows else { return }
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Smart Clipboard"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 850, height: 590)
            let contentView = NSHostingView(rootView: CaptureView(model: self))
            contentView.setAccessibilityLabel("Clipboard editor")
            window.contentView = contentView
            window.center(); panel = window
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
    func showSettings(tab: String? = nil) {
        guard presentsWindows else { return }
        refreshReadiness()
        if let tab { settingsTab = tab }
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Smart Clipboard Settings"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 640, height: 550)
            let contentView = NSHostingView(rootView: SettingsView(model: self))
            contentView.setAccessibilityLabel("Smart Clipboard settings")
            window.contentView = contentView
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func capture(window: Bool = false) {
        guard !capturing, !busy else { return }
        let preferred = defaultFormat, direction = defaultInstruction
        guard let profile = selectedProfile(requiresAI: preferred != .image) else { return }
        refreshReadiness()
        capturing = true; error = nil; notice = ""
        persistCurrentOutput()
        task = Task {
            defer { capturing = false; busy = false; task = nil }
            do {
                guard let data = try await captureClient.capture(window: window, willBegin: { [self] in
                    screenAccess = true
                    if presentsWindows { for window in NSApp.windows { window.orderOut(nil) } }
                }) else { notice = "Capture cancelled."; return }
                try Task.checkCancellation()
                capturing = false
                try await finishCapture(data, source: window ? "Window capture" : "Region capture", preferred: preferred, direction: direction, profile: profile)
            } catch is CancellationError { notice = "Capture cancelled." }
            catch { self.error = error.localizedDescription; refreshReadiness() }
        }
    }
    func importImage() {
        guard !busy, !capturing, !choosingFile else { return }
        let preferred = defaultFormat, direction = defaultInstruction
        guard let profile = selectedProfile(requiresAI: preferred != .image) else { return }
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.png, .jpeg, .tiff, .heic]; picker.canChooseDirectories = false
        choosingFile = true
        defer { choosingFile = false }
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let bitmap = NSBitmapImageRep(data: data), let normalized = bitmap.representation(using: .png, properties: [:]) else { throw ClipError.message("Could not read this image.") }
            processImportedImage(normalized, source: url.lastPathComponent, profile: profile, preferred: preferred, direction: direction)
        } catch { self.error = error.localizedDescription }
    }
    func processImportedImage(_ data: Data, source: String, profile: ConnectionProfile? = nil, preferred: OutputFormat? = nil, direction: String? = nil) {
        guard !busy, !capturing else { return }
        let preferred = preferred ?? defaultFormat, direction = direction ?? defaultInstruction
        guard let profile = profile ?? selectedProfile(requiresAI: preferred != .image) else { return }
        busy = true
        task = Task {
            defer { busy = false; task = nil }
            do { try await finishCapture(data, source: source, preferred: preferred, direction: direction, profile: profile) }
            catch is CancellationError { notice = "Conversion cancelled." }
            catch { self.error = error.localizedDescription }
        }
    }
    private func finishCapture(_ data: Data, source: String, preferred: OutputFormat, direction: String, profile: ConnectionProfile) async throws {
        acceptCapture(data, source: source)
        format = preferred; instruction = direction
        if preferred == .image { copyImage(); return }
        busy = true
        try await convertCurrent(local: false, shouldCopy: true, profile: profile, requested: preferred, extra: direction)
        // Success stays in the menu bar so the user can paste into the app they were using.
    }
    func convert(local: Bool = false) {
        guard png != nil, !busy, !capturing else { return }
        if format == .image && !local { copyImage(); return }
        let shouldCopy = copyAutomatically
        guard let profile = selectedProfile(requiresAI: !local) else { return }
        let requested = format, extra = instruction
        error = nil; busy = true
        task = Task {
            defer { busy = false; task = nil }
            do { try await convertCurrent(local: local, shouldCopy: shouldCopy, profile: profile, requested: requested, extra: extra) }
            catch is CancellationError { notice = "Conversion cancelled." }
            catch { if Task.isCancelled { notice = "Conversion cancelled." } else { self.error = error.localizedDescription } }
        }
    }
    private func convertCurrent(local: Bool, shouldCopy: Bool, profile: ConnectionProfile, requested: OutputFormat, extra: String) async throws {
        guard let png else { return }
        persistCurrentOutput()
        // Keep a history-save warning visible even when conversion itself succeeds.
        notice = ""; output = ""
        let result: ConversionResult
        var effectiveModel: String?
        if let conversionOverride { result = try await conversionOverride(png, requested, extra, local) }
        else if local { result = ConversionResult(format: .text, content: try await CaptureService.recognize(png)) }
        else {
            let converted: ProviderConversion
            if let providerConversionOverride { converted = try await providerConversionOverride(png, profile, requested, extra) }
            else { converted = try await AIService.convert(png: png, profile: profile, format: requested, instruction: extra) }
            result = converted.result; effectiveModel = converted.model
        }
        try Task.checkCancellation()
        resultFormat = result.format; output = result.content; resultInstruction = extra
        uneditedOutput = output
        resultProvenance = local ? ConversionProvenance(providerID: "apple-vision") : ConversionProvenance(providerID: profile.provider.rawValue, profileID: profile.id, requestedModel: profile.model, effectiveModel: effectiveModel)
        persistCurrentOutput()
        if shouldCopy { copyOutput() }
    }
    func cancel() { task?.cancel() }
    private func selectedProfile(requiresAI: Bool) -> ConnectionProfile? {
        guard requiresAI else { return connections.activeProfile }
        do { return try connections.validatedProfile() }
        catch { self.error = error.localizedDescription; return nil }
    }
    func clear() { guard !busy, !capturing else { return }; persistCurrentOutput(); resetCurrent() }
    private func resetCurrent() { activeHistoryID = nil; png = nil; output = ""; instruction = ""; notice = ""; resultProvenance = nil; uneditedOutput = "" }
    func acceptCapture(_ data: Data, source: String) {
        persistCurrentOutput()
        png = data; output = ""; instruction = ""; format = defaultFormat; error = nil; notice = ""; activeHistoryID = nil
        resultProvenance = nil; uneditedOutput = ""
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
        if output != uneditedOutput { resultProvenance?.userEdited = true }
        guard existing?.content != output || existing?.instruction != resultInstruction || existing?.provenance != resultProvenance else { return }
        do { try historyStore?.save(SavedConversion(format: resultFormat, content: output, instruction: resultInstruction, provenance: resultProvenance), for: id) }
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
            resultProvenance = nil; uneditedOutput = ""
            if let result = current.conversions.last { resultFormat = result.format; output = result.content; instruction = result.instruction; resultInstruction = result.instruction; resultProvenance = result.provenance; uneditedOutput = result.content }
            notice = "Opened saved capture. Choose any format to convert the original again."
            if showWindow { showPanel() }
        } catch { self.error = error.localizedDescription }
    }
    var savedConversions: [SavedConversion] { history.first(where: { $0.id == activeHistoryID })?.conversions ?? [] }
    func useSavedConversion(_ result: SavedConversion) {
        guard !busy else { return }
        persistCurrentOutput()
        resultFormat = result.format; output = result.content; instruction = result.instruction; resultInstruction = result.instruction; format = result.format
        resultProvenance = result.provenance; uneditedOutput = result.content
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
        guard presentsWindows else { return }
        persistCurrentOutput()
        if historyWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 550), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Capture History"; window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 540, height: 380)
            let contentView = NSHostingView(rootView: HistoryView(model: self))
            contentView.setAccessibilityLabel("Capture history")
            window.contentView = contentView
            window.center(); historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); historyWindow?.makeKeyAndOrderFront(nil)
    }
    func copyImage() {
        guard let png else { return }
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { error = "Could not copy the image. Try Copy image again."; return }
        notice = "Image copied."
    }
    func copyOutput() {
        persistCurrentOutput()
        guard !output.isEmpty else { return }
        pasteboard.clearContents()
        // Keep generated markup inert; don't put unreviewed HTML on the rich-text pasteboard.
        guard pasteboard.setString(output, forType: .string) else { error = "Could not copy the result. Try Copy again."; return }
        notice = "\(resultFormat.title) copied."
    }
    func save(image: Bool = false) {
        guard !choosingFile else { return }
        persistCurrentOutput()
        guard image ? png != nil : !output.isEmpty else { return }
        let ext = image ? "png" : resultFormat.fileExtension
        let dialog = NSSavePanel(); dialog.nameFieldStringValue = "Clip.\(ext)"
        dialog.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        choosingFile = true
        defer { choosingFile = false }
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        do {
            if image { try png?.write(to: url, options: .atomic) } else { try output.write(to: url, atomically: true, encoding: .utf8) }
            notice = "Saved \(url.lastPathComponent)."
        } catch { self.error = error.localizedDescription }
    }
    func setLaunchAtLogin(_ enabled: Bool) throws {
        #if ACCESSIBILITY_AUDIT
        throw ClipError.message("Accessibility audit: changing launch at login was not performed.")
        #else
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        #endif
    }
}
