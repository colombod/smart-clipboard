import AppKit
import Carbon
import ClipboardCore

/// Resolves only new defaults. Saved shortcuts remain physical key bindings.
enum ShortcutKeyResolver {
    static func key(for letter: String, modifiers: UInt32,
                    translate: (UInt16, UInt32) -> String?) -> UInt32? {
        guard letter.count == 1, letter.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) }) else { return nil }
        // Control produces control characters; Option produces symbols. Neither
        // changes the letter named by a shortcut. Command must remain because
        // layouts such as Dvorak-QWERTY-Command deliberately switch their map.
        let lookupModifiers = modifiers & UInt32(cmdKey)
        for code: UInt16 in 0...127 {
            if translate(code, lookupModifiers)?.lowercased() == letter.lowercased() { return UInt32(code) }
        }
        return nil
    }

    static func layoutData(from source: TISInputSource) -> Data? {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(value).takeUnretainedValue() as Data
    }

    static func currentKey(for letter: String, modifiers: UInt32) -> UInt32? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = layoutData(from: source) else { return nil }
        return key(for: letter, modifiers: modifiers, layoutData: data, keyboardType: UInt32(LMGetKbdType()))
    }

    /// Layout bytes come from the operating system, not an imported/user file.
    static func key(for letter: String, modifiers: UInt32, layoutData: Data, keyboardType: UInt32) -> UInt32? {
        guard layoutData.count >= MemoryLayout<UCKeyboardLayout>.size else { return nil }
        return layoutData.withUnsafeBytes { bytes in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            return key(for: letter, modifiers: modifiers) { code, flags in
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), (flags >> 8) & 0xff,
                                            keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                            &deadKeyState, characters.count, &length, &characters)
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: characters, count: length)
            }
        }
    }
}

enum ShortcutRecorderInput {
    enum Action { case cancel, navigate, assistiveNavigation, record }

    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String? = nil, voiceOverEnabled: Bool) -> Action {
        if keyCode == 53 { return .cancel }
        if voiceOverEnabled && modifiers.contains([.control, .option]) { return .assistiveNavigation }
        let commands = modifiers.intersection([.command, .control, .option])
        // Let keyboard navigation leave the recorder, restoring global handlers.
        if commands.isEmpty && [48, 115, 116, 119, 121, 123, 124, 125, 126].contains(keyCode) { return .navigate }
        if commands == .command, let character = characters?.lowercased(), ["w", "q"].contains(character) { return .navigate }
        return .record
    }
}

extension Shortcut {
    var spokenDescription: String {
        label.replacingOccurrences(of: "⌃", with: L10n.text("Control") + " ")
            .replacingOccurrences(of: "⌥", with: L10n.text("Option") + " ")
            .replacingOccurrences(of: "⇧", with: L10n.text("Shift") + " ")
            .replacingOccurrences(of: "⌘", with: L10n.text("Command") + " ")
    }
}

@MainActor protocol HotKeyBackend: AnyObject {
    var handler: ((UInt32) -> Void)? { get set }
    func register(_ shortcut: Shortcut, id: UInt32) throws
    func unregister(_ id: UInt32)
}

@MainActor final class CarbonHotKeyBackend: HotKeyBackend {
    var handler: ((UInt32) -> Void)?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var handlerStatus: OSStatus = noErr
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x53434C50 else { return OSStatus(eventNotHandledErr) }
            let backend = Unmanaged<CarbonHotKeyBackend>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { backend.handler?(id.id) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
    deinit {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
    func register(_ shortcut: Shortcut, id: UInt32) throws {
        guard handlerStatus == noErr else { throw ClipError.message(L10n.text("Keyboard event handler could not start (macOS error \(handlerStatus)). Reopen the app.")) }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: 0x53434C50, id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            if status == eventHotKeyExistsErr { throw ClipError.message(L10n.text("\(shortcut.label) is registered by another app. Choose another combination.")) }
            throw ClipError.message(L10n.text("Could not register \(shortcut.label) (macOS error \(status)). Choose another combination or reopen the app."))
        }
        refs[id] = ref
    }
    func unregister(_ id: UInt32) { if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) } }
}

@MainActor final class HotKeyManager {
    var handler: ((UInt32) -> Void)?
    private let backend: HotKeyBackend
    private let systemShortcuts: @MainActor () throws -> [Shortcut]
    private var registrations: [UInt32: (shortcut: Shortcut, token: UInt32)] = [:]
    private var nextToken: UInt32 = 100

    init(backend: HotKeyBackend? = nil, systemShortcuts: @escaping @MainActor () throws -> [Shortcut] = HotKeyManager.enabledSystemShortcuts) {
        self.backend = backend ?? CarbonHotKeyBackend()
        self.systemShortcuts = systemShortcuts
        self.backend.handler = { [weak self] token in
            guard let self, let action = self.registrations.first(where: { $0.value.token == token })?.key else { return }
            self.handler?(action)
        }
    }
    static func enabledSystemShortcuts() throws -> [Shortcut] {
        var values: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&values)
        guard status == noErr, let rows = values?.takeRetainedValue() as? [[String: Any]] else {
            throw ClipError.message(L10n.text("Could not check macOS shortcuts (error \(status)). Try Check again."))
        }
        return rows.compactMap { row in
            guard (row[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let key = row[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = row[kHISymbolicHotKeyModifiers as String] as? NSNumber else { return nil }
            return Shortcut(key: key.uint32Value, modifiers: modifiers.uint32Value, label: L10n.text("macOS shortcut"))
        }
    }
    func isRegistered(_ id: UInt32) -> Bool { registrations[id] != nil }
    func unregisterAll() {
        for value in registrations.values { backend.unregister(value.token) }
        registrations.removeAll()
    }
    func register(_ shortcut: Shortcut, id: UInt32) throws {
        guard shortcut.modifiers & UInt32(cmdKey | controlKey) != 0 else { throw ClipError.message(L10n.text("Include Command or Control.")) }
        let matches: (Shortcut) -> Bool = { $0.key == shortcut.key && $0.modifiers == shortcut.modifiers }
        guard !registrations.contains(where: { $0.key != id && matches($0.value.shortcut) }) else {
            throw ClipError.message(L10n.text("That combination is already assigned to the other capture action."))
        }
        guard try !systemShortcuts().contains(where: matches) else {
            throw ClipError.message(L10n.text("\(shortcut.label) is reserved by an enabled macOS shortcut. Choose another combination or change it in System Settings → Keyboard → Keyboard Shortcuts."))
        }
        if let old = registrations[id], matches(old.shortcut) { return }
        // Reserve the replacement first. A failed registration must leave the old key working.
        let token = nextToken; nextToken += 1
        try backend.register(shortcut, id: token)
        let old = registrations.updateValue((shortcut, token), forKey: id)
        if let old { backend.unregister(old.token) }
    }
}
