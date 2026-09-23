import AppKit
import Carbon
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import ClipboardCore

enum CaptureFeedback: Equatable {
    case copied(OutputFormat)
    case failed
}

private enum ConversionRoute: Equatable {
    case ai, appleVision, trace(TraceSettings)
    var requiresAI: Bool { self == .ai }
    var method: ConversionMethod {
        switch self { case .ai: return .ai; case .appleVision: return .appleVision; case .trace: return .vtracer }
    }
    var settings: TraceSettings? { if case .trace(let settings) = self { return settings }; return nil }
}

@MainActor final class AppModel: ObservableObject {
    @Published var png: Data?
    @Published var output = ""
    @Published var resultFormat: OutputFormat = .text
    @Published var format: OutputFormat = .auto
    @Published var outputLanguage: OutputLanguage = .source
    @Published var svgMethod: SVGMethod = .ai
    @Published var traceSettings = TraceSettings()
    @Published private(set) var resultOutputLanguage: String?
    @Published var instruction = ""
    @Published var busy = false
    @Published var capturing = false
    @Published private(set) var choosingFile = false
    @Published var error: String?
    @Published var notice = "" { didSet { operationNotice = .none } }
    @Published private(set) var operationNotice: AccessibilityStatusSnapshot.Notice = .none
    @Published var settingsTab = "connection"
    let connections: ConnectionStore
    // Supplied only by the production app lifecycle, never by tests or audit builds.
    var updates: UpdateController?
    var notifications: CaptureNotifications?
    // Explicit operation events avoid treating history warnings or UI refreshes as captures.
    var operationFeedback: ((CaptureFeedback) -> Void)?
    @Published var defaultFormat: OutputFormat { didSet { defaults.set(defaultFormat.rawValue, forKey: "defaultFormat") } }
    @Published var defaultInstruction: String { didSet { defaults.set(defaultInstruction, forKey: "defaultInstruction") } }
    @Published var defaultOutputLanguage: OutputLanguage { didSet { defaults.set(defaultOutputLanguage.rawValue, forKey: "defaultOutputLanguage") } }
    @Published var defaultSVGMethod: SVGMethod { didSet { defaults.set(defaultSVGMethod.rawValue, forKey: "defaultSVGMethod") } }
    @Published var defaultTraceSettings: TraceSettings { didSet { defaults.set(try? JSONEncoder().encode(defaultTraceSettings), forKey: "defaultTraceSettings") } }
    var usesTracing: Bool { format == .svg && svgMethod == .trace }
    var defaultUsesTracing: Bool { defaultFormat == .svg && defaultSVGMethod == .trace }
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
    private var resultMethod: ConversionMethod = .ai
    private var resultTraceSettings: TraceSettings?
    private var persistedOutput: String?
    private var persistedVariantID: String?
    private var validatedSVG: String?
    var resultOrigin: String? {
        guard let provenance = resultProvenance else { return nil }
        if provenance.providerID == "vtracer" {
            let origin = L10n.text("Local tracing") + " · VTracer " + (provenance.effectiveModel ?? provenance.requestedModel)
            return provenance.userEdited ? L10n.text("\(origin) · Edited") : origin
        }
        let provider = AIProvider(rawValue: provenance.providerID)?.title ?? L10n.text("On-device text extraction")
        let model = provenance.effectiveModel ?? (provenance.requestedModel.isEmpty ? L10n.text("Default model") : provenance.requestedModel)
        let origin = provenance.providerID == "apple-vision" ? provider : "\(provider) · \(model)"
        return provenance.userEdited ? L10n.text("\(origin) · Edited") : origin
    }
    private var historyStore: HistoryStore?
    private var historyWindow: NSWindow?
    @Published var menuBarInstalled = false
    @Published private(set) var screenAccess = false
    @Published private(set) var shortcutProblems: [UInt32: String] = [:]
    @Published private(set) var shortcutsPaused = false
    @Published private(set) var lastShortcutEvent = L10n.text("No shortcut received yet")
    private let pasteboard: NSPasteboard
    private let presentsWindows: Bool
    private let conversionOverride: ((Data, OutputFormat, String, Bool) async throws -> ConversionResult)?
    private let providerConversionOverride: ((Data, ConnectionProfile, OutputFormat, String) async throws -> ProviderConversion)?
    private let traceOverride: ((Data, TraceSettings) async throws -> VectorTraceResult)?
    private let captureClient: CaptureClient
    private let registersHotkeys: Bool
    private let systemLanguage: () -> String
    let hotkeys: HotKeyManager
    var captureReady: Bool { screenAccess && !shortcutsPaused && shortcutProblems.isEmpty && hotkeys.isRegistered(1) && hotkeys.isRegistered(2) }
    func shortcutStatus(_ id: UInt32) -> String {
        if shortcutsPaused { return L10n.text("Paused while recording a shortcut") }
        if let problem = shortcutProblems[id] { return problem }
        return hotkeys.isRegistered(id) ? L10n.text("Registered and listening") : L10n.text("Not registered")
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

    init(defaults: UserDefaults = .standard, historyDirectory: URL? = nil, registerHotkeys: Bool = true, hotkeyManager: HotKeyManager? = nil, captureClient: CaptureClient? = nil, pasteboard: NSPasteboard? = nil, presentsWindows: Bool = true, conversionOverride: ((Data, OutputFormat, String, Bool) async throws -> ConversionResult)? = nil, providerConversionOverride: ((Data, ConnectionProfile, OutputFormat, String) async throws -> ProviderConversion)? = nil, traceOverride: ((Data, TraceSettings) async throws -> VectorTraceResult)? = nil, systemLanguage: @escaping () -> String = { OutputLanguage.systemLanguageIdentifier }) {
        self.pasteboard = pasteboard ?? .general
        self.presentsWindows = presentsWindows
        self.conversionOverride = conversionOverride
        self.providerConversionOverride = providerConversionOverride
        self.traceOverride = traceOverride
        self.captureClient = captureClient ?? CaptureClient()
        self.hotkeys = hotkeyManager ?? HotKeyManager()
        self.registersHotkeys = registerHotkeys
        self.systemLanguage = systemLanguage
        self.defaults = defaults
        self.connections = ConnectionStore(defaults: defaults)
        historyLimit = defaults.object(forKey: "historyLimit") == nil ? HistoryStore.defaultLimit : min(max(0, defaults.integer(forKey: "historyLimit")), HistoryStore.maximumLimit)
        defaultFormat = OutputFormat(rawValue: defaults.string(forKey: "defaultFormat") ?? "") ?? .auto
        defaultSVGMethod = SVGMethod(rawValue: defaults.string(forKey: "defaultSVGMethod") ?? "") ?? .ai
        defaultTraceSettings = defaults.data(forKey: "defaultTraceSettings").flatMap { try? JSONDecoder().decode(TraceSettings.self, from: $0) } ?? TraceSettings()
        let savedDirection = defaults.string(forKey: "defaultInstruction") ?? ""
        defaultInstruction = savedDirection
        if let savedLanguage = defaults.string(forKey: "defaultOutputLanguage") {
            defaultOutputLanguage = OutputLanguage(rawValue: savedLanguage) ?? .source
        } else {
            // Existing translation directions must not silently stop working on upgrade.
            let migratedLanguage: OutputLanguage = savedDirection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .source : .directions
            defaultOutputLanguage = migratedLanguage
            defaults.set(migratedLanguage.rawValue, forKey: "defaultOutputLanguage")
        }
        copyAutomatically = defaults.bool(forKey: "copyAutomatically")
        regionShortcut = Self.loadShortcut("regionShortcut", defaults: defaults) ?? .region
        windowShortcut = Self.loadShortcut("windowShortcut", defaults: defaults) ?? .window
        svgMethod = defaultSVGMethod
        traceSettings = defaultTraceSettings
        hotkeys.handler = { [weak self] id in
            guard let self else { return }
            let time = Date().formatted(date: .omitted, time: .standard)
            self.lastShortcutEvent = id == 2 ? L10n.text("Window shortcut received at \(time)") : L10n.text("Region shortcut received at \(time)")
            self.capture(window: id == 2)
        }
        if registerHotkeys { refreshReadiness() }
        do {
            let directory = historyDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Smart Clipboard/History", isDirectory: true)
            historyStore = try HistoryStore(directory: directory, limit: historyLimit)
            refreshHistory()
        } catch { self.error = L10n.text("Could not open capture history: \(error.localizedDescription)") }
    }
    static func loadShortcut(_ key: String, defaults: UserDefaults) -> Shortcut? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }
    func setShortcut(_ shortcut: Shortcut, window: Bool) throws {
        let other = window ? regionShortcut : windowShortcut
        guard shortcut.key != other.key || shortcut.modifiers != other.modifiers else { throw ClipError.message(L10n.text("Use different shortcuts for region and window capture.")) }
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
            window.minSize = NSSize(width: 900, height: 700)
            let contentView = NSHostingView(rootView: CaptureView(model: self))
            contentView.setAccessibilityLabel(L10n.text("Clipboard editor"))
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
            window.title = L10n.text("Smart Clipboard Settings")
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 640, height: 550)
            let contentView = NSHostingView(rootView: SettingsView(model: self))
            contentView.setAccessibilityLabel(L10n.text("Smart Clipboard settings"))
            window.contentView = contentView
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func capture(window: Bool = false) {
        guard !capturing, !busy else { return }
        let preferred = defaultFormat, direction = defaultInstruction
        let route: ConversionRoute = defaultUsesTracing ? .trace(defaultTraceSettings) : .ai
        let language = route.settings == nil ? defaultOutputLanguage : .source
        let resolvedLanguage = language.resolvedIdentifier(systemLanguage: systemLanguage())
        guard let profile = selectedProfile(requiresAI: preferred != .image && route.requiresAI) else { return }
        refreshReadiness()
        capturing = true; error = nil; notice = ""
        persistCurrentOutput()
        task = Task {
            defer { capturing = false; busy = false; task = nil }
            do {
                try Task.checkCancellation()
                guard let data = try await captureClient.capture(window: window, willBegin: { [self] in
                    screenAccess = true
                    if presentsWindows { for window in NSApp.windows { window.orderOut(nil) } }
                }) else { setOperationNotice(.captureCancelled); return }
                try Task.checkCancellation()
                capturing = false
                try await finishCapture(data, source: window ? L10n.text("Window capture") : L10n.text("Region capture"), preferred: preferred, direction: direction, profile: profile, language: language, resolvedLanguage: resolvedLanguage, route: route)
            } catch is CancellationError { setOperationNotice(.captureCancelled) }
            catch {
                if Task.isCancelled { setOperationNotice(.captureCancelled) }
                else { reportOperationFailure(error.localizedDescription); refreshReadiness() }
            }
        }
    }
    func importImage() {
        guard !busy, !capturing, !choosingFile else { return }
        let preferred = defaultFormat, direction = defaultInstruction
        let route: ConversionRoute = defaultUsesTracing ? .trace(defaultTraceSettings) : .ai
        let language = route.settings == nil ? defaultOutputLanguage : .source
        let resolvedLanguage = language.resolvedIdentifier(systemLanguage: systemLanguage())
        guard let profile = selectedProfile(requiresAI: preferred != .image && route.requiresAI) else { return }
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.png, .jpeg, .tiff, .heic]; picker.canChooseDirectories = false
        choosingFile = true
        defer { choosingFile = false }
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let bitmap = NSBitmapImageRep(data: data), let normalized = bitmap.representation(using: .png, properties: [:]) else { throw ClipError.message(L10n.text("Could not read this image.")) }
            startImportedImage(normalized, source: url.lastPathComponent, profile: profile, preferred: preferred, direction: direction, language: language, resolvedLanguage: resolvedLanguage, route: route)
        } catch { reportOperationFailure(error.localizedDescription) }
    }
    func processImportedImage(_ data: Data, source: String, profile: ConnectionProfile? = nil, preferred: OutputFormat? = nil, direction: String? = nil, language: OutputLanguage? = nil) {
        guard !busy, !capturing else { return }
        let preferred = preferred ?? defaultFormat, direction = direction ?? defaultInstruction
        let route: ConversionRoute = preferred == .svg && defaultSVGMethod == .trace ? .trace(defaultTraceSettings) : .ai
        guard let profile = profile ?? selectedProfile(requiresAI: preferred != .image && route.requiresAI) else { return }
        let language = route.settings == nil ? (language ?? defaultOutputLanguage) : .source
        startImportedImage(data, source: source, profile: profile, preferred: preferred, direction: direction, language: language, resolvedLanguage: language.resolvedIdentifier(systemLanguage: systemLanguage()), route: route)
    }
    private func startImportedImage(_ data: Data, source: String, profile: ConnectionProfile, preferred: OutputFormat, direction: String, language: OutputLanguage, resolvedLanguage: String?, route: ConversionRoute) {
        busy = true
        task = Task {
            defer { busy = false; task = nil }
            do { try await finishCapture(data, source: source, preferred: preferred, direction: direction, profile: profile, language: language, resolvedLanguage: resolvedLanguage, route: route) }
            catch is CancellationError { setOperationNotice(.conversionCancelled) }
            catch {
                if Task.isCancelled { setOperationNotice(.conversionCancelled) }
                else { reportOperationFailure(error.localizedDescription) }
            }
        }
    }
    private func finishCapture(_ data: Data, source: String, preferred: OutputFormat, direction: String, profile: ConnectionProfile, language: OutputLanguage, resolvedLanguage: String?, route: ConversionRoute) async throws {
        try Task.checkCancellation()
        acceptCapture(data, source: source)
        format = preferred; instruction = direction; outputLanguage = language
        svgMethod = route.settings == nil ? .ai : .trace
        if let settings = route.settings { traceSettings = settings }
        if preferred == .image { copyImage(); return }
        busy = true
        try await convertCurrent(route: route, shouldCopy: true, profile: profile, requested: preferred, extra: direction, resolvedLanguage: resolvedLanguage)
        // Success stays in the menu bar so the user can paste into the app they were using.
    }
    func convert(local: Bool = false) {
        guard png != nil, !busy, !capturing else { return }
        if format == .image && !local { copyImage(); return }
        let shouldCopy = copyAutomatically
        let route: ConversionRoute = local ? .appleVision : (usesTracing ? .trace(traceSettings) : .ai)
        guard let profile = selectedProfile(requiresAI: route.requiresAI) else { return }
        let requested = format, extra = instruction
        let resolvedLanguage = route.requiresAI ? outputLanguage.resolvedIdentifier(systemLanguage: systemLanguage()) : nil
        error = nil; busy = true
        task = Task {
            defer { busy = false; task = nil }
            do { try await convertCurrent(route: route, shouldCopy: shouldCopy, profile: profile, requested: requested, extra: extra, resolvedLanguage: resolvedLanguage) }
            catch is CancellationError { setOperationNotice(.conversionCancelled) }
            catch { if Task.isCancelled { setOperationNotice(.conversionCancelled) } else { reportOperationFailure(error.localizedDescription) } }
        }
    }
    private func convertCurrent(route: ConversionRoute, shouldCopy: Bool, profile: ConnectionProfile, requested: OutputFormat, extra: String, resolvedLanguage: String?) async throws {
        guard let png else { return }
        persistCurrentOutput()
        // Keep a history-save warning visible even when conversion itself succeeds.
        notice = ""; output = ""; persistedOutput = nil; persistedVariantID = nil
        let result: ConversionResult
        let local = route == .appleVision
        let providerInstruction = local ? extra : OutputLanguage.instruction(userInstruction: extra, resolvedIdentifier: resolvedLanguage)
        var effectiveModel: String?
        if let settings = route.settings {
            let traced: VectorTraceResult
            if let traceOverride { traced = try await traceOverride(png, settings) }
            else { traced = try await VectorTraceService().trace(png: png, settings: settings) }
            result = ConversionResult(format: .svg, content: traced.svg)
            effectiveModel = traced.engineVersion
        }
        else if let conversionOverride { result = try await conversionOverride(png, requested, providerInstruction, local) }
        else if local { result = ConversionResult(format: .text, content: try await CaptureService.recognize(png)) }
        else {
            let converted: ProviderConversion
            if let providerConversionOverride { converted = try await providerConversionOverride(png, profile, requested, providerInstruction) }
            else { converted = try await AIService.convert(png: png, profile: profile, format: requested, instruction: providerInstruction) }
            result = converted.result; effectiveModel = converted.model
        }
        try Task.checkCancellation()
        if result.format == .svg { try validateSVG(result.content) }
        resultMethod = route.method; resultTraceSettings = route.settings
        resultFormat = result.format; output = result.content; resultInstruction = route.settings == nil ? extra : ""; resultOutputLanguage = resolvedLanguage
        uneditedOutput = output
        if route.settings != nil { resultProvenance = ConversionProvenance(providerID: "vtracer", effectiveModel: effectiveModel) }
        else { resultProvenance = local ? ConversionProvenance(providerID: "apple-vision") : ConversionProvenance(providerID: profile.provider.rawValue, profileID: profile.id, requestedModel: profile.model, effectiveModel: effectiveModel) }
        persistCurrentOutput()
        if shouldCopy { copyOutput() }
    }
    private func setOperationNotice(_ value: AccessibilityStatusSnapshot.Notice) {
        notice = value.message
        operationNotice = value
    }
    func cancel() { task?.cancel() }
    private func selectedProfile(requiresAI: Bool) -> ConnectionProfile? {
        guard requiresAI else { return connections.activeProfile }
        do { return try connections.validatedProfile() }
        catch { reportOperationFailure(error.localizedDescription); return nil }
    }
    private func reportOperationFailure(_ message: String) {
        error = message
        operationFeedback?(.failed)
    }
    func clear() { guard !busy, !capturing else { return }; persistCurrentOutput(); resetCurrent() }
    private func resetCurrent() {
        activeHistoryID = nil; png = nil; output = ""; instruction = ""; notice = ""; resultProvenance = nil; uneditedOutput = ""
        resultOutputLanguage = nil; outputLanguage = defaultOutputLanguage
        resultMethod = .ai; resultTraceSettings = nil; persistedOutput = nil; persistedVariantID = nil; validatedSVG = nil
        svgMethod = defaultSVGMethod; traceSettings = defaultTraceSettings
    }
    func acceptCapture(_ data: Data, source: String) {
        persistCurrentOutput()
        png = data; output = ""; instruction = ""; format = defaultFormat; error = nil; notice = ""; activeHistoryID = nil
        resultProvenance = nil; uneditedOutput = ""
        resultOutputLanguage = nil; outputLanguage = defaultOutputLanguage
        resultMethod = .ai; resultTraceSettings = nil; persistedOutput = nil; persistedVariantID = nil; validatedSVG = nil
        svgMethod = defaultSVGMethod; traceSettings = defaultTraceSettings
        do {
            guard let historyStore else { throw ClipError.message(L10n.text("History storage is unavailable. Check the local history folder before saving more clips.")) }
            activeHistoryID = try historyStore.add(png: data, source: source)?.id
        }
        catch { self.error = L10n.text("Capture opened, but could not save history: \(error.localizedDescription)") }
        refreshHistory()
    }
    private func refreshHistory() {
        history = historyStore?.entries ?? []
        historyBytes = historyStore?.diskBytes ?? 0
        if let id = activeHistoryID, !history.contains(where: { $0.id == id }) { activeHistoryID = nil }
    }
    func persistCurrentOutput() {
        guard let id = activeHistoryID, !output.isEmpty else { return }
        if resultFormat == .svg {
            do { try validateSVG(output) }
            catch { self.error = error.localizedDescription; return }
        }
        if output != uneditedOutput { resultProvenance?.userEdited = true }
        let saved = SavedConversion(format: resultFormat, content: output, instruction: resultInstruction, provenance: resultProvenance, outputLanguage: resultOutputLanguage, method: resultMethod, traceSettings: resultTraceSettings)
        let existing = history.first(where: { $0.id == id })?.conversions.last(where: { $0.id == saved.id })
        let unchangedContent = existing?.content == output || (persistedVariantID == saved.id && persistedOutput == output)
        guard !unchangedContent || existing?.instruction != resultInstruction || existing?.provenance != resultProvenance else { return }
        do {
            guard let historyStore else { throw ClipError.message(L10n.text("History storage is unavailable.")) }
            try historyStore.save(saved, for: id)
            persistedOutput = output; persistedVariantID = saved.id
        }
        catch { self.error = L10n.text("Could not save the result in history: \(error.localizedDescription)") }
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
            resultOutputLanguage = nil; outputLanguage = defaultOutputLanguage
            resultMethod = .ai; resultTraceSettings = nil; persistedOutput = nil; persistedVariantID = nil
            svgMethod = defaultSVGMethod; traceSettings = defaultTraceSettings
            if let result = current.conversions.last {
                // A broken result must not hide an intact original or prevent
                // choosing another saved version and trying the conversion again.
                do { try loadSavedConversion(result) }
                catch { self.error = error.localizedDescription }
            }
            notice = L10n.text("Opened saved capture. Choose a format and language to convert the original again.")
            if showWindow { showPanel() }
        } catch { self.error = error.localizedDescription }
    }
    var savedConversions: [SavedConversion] { history.first(where: { $0.id == activeHistoryID })?.conversions ?? [] }
    func useSavedConversion(_ result: SavedConversion) {
        guard !busy else { return }
        persistCurrentOutput()
        do {
            try loadSavedConversion(result)
            notice = L10n.text("Loaded saved \(result.format.title).")
        } catch { self.error = error.localizedDescription }
    }
    private func loadSavedConversion(_ result: SavedConversion) throws {
        guard let id = activeHistoryID, let historyStore else { return }
        let content = try historyStore.content(for: result, in: id)
        if result.format == .svg { try validateSVG(content) }
        resultFormat = result.format; output = content; instruction = result.instruction; resultInstruction = result.instruction; format = result.format
        resultProvenance = result.provenance; uneditedOutput = content
        resultOutputLanguage = result.outputLanguage; outputLanguage = .fromResolvedIdentifier(result.outputLanguage)
        resultMethod = result.method; resultTraceSettings = result.traceSettings
        svgMethod = result.method == .vtracer ? .trace : .ai
        traceSettings = result.traceSettings ?? defaultTraceSettings
        persistedOutput = content; persistedVariantID = result.id
    }
    func historyImageURL(_ entry: HistoryEntry) -> URL? { historyStore?.imageURL(for: entry.id) }
    func setHistoryLimit(_ value: Int) {
        guard !busy, !capturing else { return }
        persistCurrentOutput()
        do {
            guard let historyStore else { throw ClipError.message(L10n.text("History storage is unavailable.")) }
            try historyStore.setLimit(value)
            historyLimit = historyStore.limit; defaults.set(historyLimit, forKey: "historyLimit")
            if historyLimit == 0 { resetCurrent() }
        } catch { self.error = error.localizedDescription }
        refreshHistory()
    }
    func deleteHistory(_ entry: HistoryEntry) {
        guard !busy, !capturing else { return }
        do {
            guard let historyStore else { throw ClipError.message(L10n.text("History storage is unavailable; no files were deleted.")) }
            try historyStore.remove(entry.id)
            if activeHistoryID == entry.id { resetCurrent() }
        } catch { self.error = error.localizedDescription }
        refreshHistory()
    }
    func clearHistory() {
        guard !busy, !capturing else { return }
        do {
            guard let historyStore else { throw ClipError.message(L10n.text("History storage is unavailable; no files were deleted.")) }
            try historyStore.clear(); resetCurrent(); notice = L10n.text("History cleared.")
        }
        catch { self.error = error.localizedDescription }
        refreshHistory()
    }
    func showHistory() {
        guard presentsWindows else { return }
        persistCurrentOutput()
        if historyWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 550), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = L10n.text("Capture History"); window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 540, height: 380)
            let contentView = NSHostingView(rootView: HistoryView(model: self))
            contentView.setAccessibilityLabel(L10n.text("Capture history"))
            window.contentView = contentView
            window.center(); historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); historyWindow?.makeKeyAndOrderFront(nil)
    }
    func copyImage() {
        guard let png else { return }
        guard ClipboardWriter.writePNG(png, to: pasteboard) else {
            reportOperationFailure(L10n.text("Could not copy the image. Try Copy image again.")); return
        }
        setOperationNotice(.imageCopied)
        operationFeedback?(.copied(.image))
    }
    func copyOutput() {
        guard !output.isEmpty else { return }
        if resultFormat == .svg {
            do { try validateSVG(output) }
            catch { reportOperationFailure(error.localizedDescription); return }
        }
        persistCurrentOutput()
        // Keep generated markup inert; don't put unreviewed HTML on the rich-text pasteboard.
        guard ClipboardWriter.writeText(output, to: pasteboard) else {
            reportOperationFailure(L10n.text("Could not copy the result. Try Copy again.")); return
        }
        setOperationNotice(.resultCopied(resultFormat))
        operationFeedback?(.copied(resultFormat))
    }
    func save(image: Bool = false) {
        guard !choosingFile else { return }
        if !image, resultFormat == .svg {
            do { try validateSVG(output) }
            catch { reportOperationFailure(error.localizedDescription); return }
        }
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
            notice = L10n.text("Saved \(url.lastPathComponent).")
        } catch { self.error = error.localizedDescription }
    }
    private func validateSVG(_ content: String) throws {
        guard validatedSVG != content else { return }
        try SVGValidator.validate(content)
        validatedSVG = content
    }
    func setLaunchAtLogin(_ enabled: Bool) throws {
        #if ACCESSIBILITY_AUDIT
        throw ClipError.message("Accessibility audit: changing launch at login was not performed.")
        #else
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        #endif
    }
}
