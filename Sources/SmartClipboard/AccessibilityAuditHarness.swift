#if ACCESSIBILITY_AUDIT
import AppKit
import ClipboardCore

/// Compiled only into the separate accessibility-audit application. The normal
/// application cannot enable this harness with command-line arguments.
@MainActor final class AccessibilityAuditHarness {
    let model: AppModel
    private(set) var isReady = false
    private(set) var announcements: [String] = []
    lazy var announcer: AccessibilityStatusAnnouncer = {
        if CommandLine.arguments.contains("--audit-voiceover-announcements") {
            return .live()
        }
        return AccessibilityStatusAnnouncer(isVoiceOverEnabled: { true }) { [weak self] message in
            self?.announcements.append(message)
        }
    }()

    private let fixture: Data
    private let historyDirectory: URL
    private let pasteboard: NSPasteboard
    private var launchTask: Task<Void, Never>?
    private var windowObserver: NSObjectProtocol?

    init() {
        precondition(Bundle.main.bundleIdentifier == "com.smartclipboard.accessibility-audit",
                     "ACCESSIBILITY_AUDIT requires the isolated audit bundle identifier")
        let token = UUID().uuidString
        historyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartClipboardAccessibilityAudit." + token, isDirectory: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("SmartClipboardAccessibilityAudit." + token))
        fixture = Self.makeFixture()
        let image = fixture
        let defaults = AccessibilityAuditDefaults(auditID: token)
        defaults.set(OutputFormat.markdown.rawValue, forKey: "defaultFormat")
        defaults.set(true, forKey: "copyAutomatically")
        let hotkeys = HotKeyManager(backend: AccessibilityAuditHotKeys(), systemShortcuts: { [] })
        let capture = CaptureClient(hasAccess: { true }, requestAccess: { false }, takeImage: { _ in image })
        model = AppModel(defaults: defaults, historyDirectory: historyDirectory, registerHotkeys: true,
                         hotkeyManager: hotkeys, captureClient: capture, pasteboard: pasteboard,
                         presentsWindows: true, conversionOverride: { _, format, _, _ in Self.mockConversion(format) })
        model.connections.update(ConnectionProfile(provider: .omlx, model: "synthetic-accessibility-model",
                                                   endpoint: "http://127.0.0.1:1/v1"))
        model.connections.activeProvider = .omlx
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                               object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.identify(notification.object as? NSWindow) }
        }
    }

    /// No screen argument means normal quiet menu-bar startup. Fixture creation
    /// also stays hidden until an explicit window request is made.
    func launch(arguments: [String]) {
        if let index = arguments.firstIndex(of: "--audit-provider") {
            guard arguments.indices.contains(index + 1), let provider = AIProvider(rawValue: arguments[index + 1]) else {
                model.error = "Accessibility audit needs a supported --audit-provider value. No window was opened."
                return
            }
            model.connections.activeProvider = provider
        }
        let screen: String?
        if let index = arguments.firstIndex(of: "--audit-screen") {
            let supported = ["settings-general", "settings-shortcuts", "settings-connection",
                             "settings-history", "settings-about", "editor", "history"]
            guard arguments.indices.contains(index + 1), supported.contains(arguments[index + 1]) else {
                model.error = "Accessibility audit needs a supported --audit-screen value. No window was opened."
                return
            }
            screen = arguments[index + 1]
        } else { screen = nil }
        let populated = arguments.contains("--audit-populated")
        launchTask = Task { [weak self] in
            guard let self else { return }
            defer { self.launchTask = nil }
            if populated {
                self.model.processImportedImage(self.fixture, source: "Synthetic accessibility fixture",
                                                profile: self.model.connections.activeProfile, preferred: .markdown)
                let deadline = Date().addingTimeInterval(5)
                while self.model.busy || self.model.capturing {
                    guard Date() < deadline, !Task.isCancelled else { return }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                guard self.model.error == nil, !self.model.output.isEmpty, !self.model.history.isEmpty else { return }
            }
            self.isReady = true
            switch screen {
            case "editor": self.model.showPanel()
            case "history": self.model.showHistory()
            case .some(let name): self.model.showSettings(tab: String(name.dropFirst("settings-".count)))
            case nil: break
            }
            NSApp.windows.forEach { self.identify($0) }
        }
    }

    private func identify(_ window: NSWindow?) {
        guard isReady, let window else { return }
        let identifier: String
        switch window.title {
        case "Smart Clipboard": identifier = "accessibility-audit.editor"
        case "Smart Clipboard Settings": identifier = "accessibility-audit.settings"
        case "Capture History": identifier = "accessibility-audit.history"
        default: return
        }
        window.setAccessibilityIdentifier(identifier)
    }

    func cleanup() {
        launchTask?.cancel()
        model.cancel()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: historyDirectory)
    }

    private static func makeFixture() -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 520, pixelsHigh: 190,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            preconditionFailure("Could not create the synthetic accessibility image")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 520, height: 190).fill()
        let rows = ["Accessibility sample", "Item                 Quantity", "Apples              3", "Pears                2"]
        for (index, row) in rows.enumerated() {
            (row as NSString).draw(at: NSPoint(x: 24, y: CGFloat(144 - index * 36)),
                                  withAttributes: [.font: NSFont.systemFont(ofSize: index == 0 ? 24 : 20),
                                                   .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Could not encode the synthetic accessibility image")
        }
        return png
    }

    nonisolated private static func mockConversion(_ requested: OutputFormat) -> ConversionResult {
        let format: OutputFormat = requested == .auto || requested == .image ? .markdown : requested
        let content: String
        switch format {
        case .description: content = "A synthetic table lists three apples and two pears beneath the heading Accessibility sample."
        case .text: content = "Accessibility sample\nItem\tQuantity\nApples\t3\nPears\t2"
        case .json: content = "{\"items\":[{\"name\":\"Apples\",\"quantity\":3},{\"name\":\"Pears\",\"quantity\":2}]}"
        case .yaml: content = "items:\n  - name: Apples\n    quantity: 3\n  - name: Pears\n    quantity: 2"
        case .html: content = "<table><caption>Accessibility sample</caption><tr><th>Item</th><th>Quantity</th></tr><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>2</td></tr></table>"
        case .svg: content = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 300 120\"><text x=\"12\" y=\"30\">Accessibility sample</text><text x=\"12\" y=\"65\">Apples: 3</text><text x=\"12\" y=\"100\">Pears: 2</text></svg>"
        default: content = "# Accessibility sample\n\n| Item | Quantity |\n| --- | --- |\n| Apples | 3 |\n| Pears | 2 |"
        }
        return ConversionResult(format: format, content: content)
    }
}

/// This backend only records registrations in HotKeyManager's own dictionary.
/// It never installs Carbon event handlers or reserves system-wide shortcuts.
@MainActor private final class AccessibilityAuditHotKeys: HotKeyBackend {
    var handler: ((UInt32) -> Void)?
    func register(_ shortcut: Shortcut, id: UInt32) throws {}
    func unregister(_ id: UInt32) {}
}

/// All app preference reads/writes stay in memory, including ConnectionStore's
/// migration and serialization paths. No standard defaults domain is consulted.
private final class AccessibilityAuditDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    init(auditID: String) { super.init(suiteName: "AccessibilityAuditMemory." + auditID)! }
    override func object(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }; return values[key]
    }
    override func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }; values[key] = value
    }
    override func set(_ value: Bool, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func set(_ value: Int, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func set(_ value: Double, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func removeObject(forKey key: String) { set(nil, forKey: key) }
    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    override func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? false }
    override func integer(forKey key: String) -> Int { (object(forKey: key) as? NSNumber)?.intValue ?? 0 }
    override func double(forKey key: String) -> Double { (object(forKey: key) as? NSNumber)?.doubleValue ?? 0 }
    override func dictionaryRepresentation() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }; return values
    }
}
#endif
