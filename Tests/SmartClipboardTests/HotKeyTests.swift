import AppKit
import Carbon
import ClipboardCore
import Foundation
import Testing
@testable import SmartClipboard

@MainActor private final class FakeHotKeyBackend: HotKeyBackend {
    var handler: ((UInt32) -> Void)?
    var held: [UInt32: Shortcut] = [:]
    var unavailable: [Shortcut] = []
    func register(_ shortcut: Shortcut, id: UInt32) throws {
        if unavailable.contains(where: { $0.key == shortcut.key && $0.modifiers == shortcut.modifiers }) {
            throw ClipError.message("Already registered by another app")
        }
        held[id] = shortcut
    }
    func unregister(_ id: UInt32) { held[id] = nil }
}

@MainActor struct HotKeyTests {
    @Test func failedReplacementKeepsOldRegistrationAndHandler() throws {
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(backend: backend, systemShortcuts: { [] })
        try manager.register(.region, id: 1)
        let oldToken = try #require(backend.held.keys.first)
        backend.unavailable = [.window]
        #expect(throws: (any Error).self) { try manager.register(.window, id: 1) }
        #expect(backend.held[oldToken] == .region)
        var received: UInt32?
        manager.handler = { received = $0 }
        backend.handler?(oldToken)
        #expect(received == 1)
    }
    @Test func replacementRemovesOldKeyAndMapsNewTokenToSameAction() throws {
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(backend: backend, systemShortcuts: { [] })
        try manager.register(.region, id: 1)
        let oldToken = try #require(backend.held.keys.first)
        try manager.register(.window, id: 1)
        #expect(backend.held.count == 1)
        #expect(backend.held[oldToken] == nil)
        var events: [UInt32] = []
        manager.handler = { events.append($0) }
        backend.handler?(oldToken)
        backend.handler?(try #require(backend.held.keys.first))
        #expect(events == [1])
    }
    @Test func reservedSystemShortcutRejectedBeforeRegistration() {
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(backend: backend, systemShortcuts: { [.region] })
        #expect(throws: (any Error).self) { try manager.register(.region, id: 1) }
        #expect(backend.held.isEmpty)
    }
    @Test func duplicateActionShortcutRejectedButSameBindingIsIdempotent() throws {
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(backend: backend, systemShortcuts: { [] })
        try manager.register(.region, id: 1)
        try manager.register(.region, id: 1)
        #expect(throws: (any Error).self) { try manager.register(.region, id: 2) }
        #expect(backend.held.count == 1)
    }
    @Test func startupRegistersSecondShortcutWhenFirstConflictsAndFindsAlternative() throws {
        let backend = FakeHotKeyBackend(); backend.unavailable = [.region]
        let manager = HotKeyManager(backend: backend, systemShortcuts: { [] })
        let suite = "HotKeyTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(defaults: defaults, historyDirectory: directory, hotkeyManager: manager)
        #expect(model.shortcutProblems[1] != nil)
        #expect(model.shortcutProblems[2] == nil)
        #expect(manager.isRegistered(2))
        model.findAvailableShortcuts()
        #expect(model.regionShortcut != .region)
        #expect(model.regionShortcut.key == Shortcut.region.key)
        #expect(model.regionShortcut.label.hasSuffix("R"))
        #expect(model.windowShortcut == .window)
        #expect(model.shortcutProblems.isEmpty)
        #expect(manager.isRegistered(1))
        #expect(AppModel.loadShortcut("regionShortcut", defaults: defaults) == model.regionShortcut)
        model.pauseShortcuts()
        #expect(backend.held.isEmpty)
        #expect(model.shortcutsPaused)
        model.resumeShortcuts()
        #expect(backend.held.count == 2)
        #expect(!model.shortcutsPaused)
    }
    @Test func newDefaultsUseLettersAndSavedBindingsSurviveAnUpgrade() throws {
        let custom = [
            Shortcut(key: 10, modifiers: UInt32(controlKey | optionKey), label: "⌃⌥§"),
            Shortcut(key: 10, modifiers: UInt32(controlKey | optionKey | shiftKey), label: "⌃⌥⇧§")
        ]
        let oldNumbers = [
            Shortcut(key: 20, modifiers: UInt32(cmdKey | optionKey | shiftKey), label: "⌥⇧⌘3"),
            Shortcut(key: 21, modifiers: UInt32(cmdKey | optionKey | shiftKey), label: "⌥⇧⌘4")
        ]
        for saved in [[], custom, oldNumbers] {
            let suite = "HotKeyDefaultsTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
            for (key, value) in zip(["regionShortcut", "windowShortcut"], saved) {
                defaults.set(try JSONEncoder().encode(value), forKey: key)
            }
            let backend = FakeHotKeyBackend()
            let manager = HotKeyManager(backend: backend, systemShortcuts: { [] })
            var lookups = 0
            let model = AppModel(defaults: defaults, historyDirectory: directory,
                                 hotkeyManager: manager, presentsWindows: false, shortcutKeyResolver: { letter, _ in
                lookups += 1
                return UInt32(letter == "R" ? kVK_ANSI_R : kVK_ANSI_W)
            })
            if saved.isEmpty {
                #expect(model.regionShortcut.key == UInt32(kVK_ANSI_R))
                #expect(model.windowShortcut.key == UInt32(kVK_ANSI_W))
                #expect(model.regionShortcut.modifiers == UInt32(controlKey | cmdKey))
                #expect(model.windowShortcut.modifiers == UInt32(controlKey | cmdKey))
                #expect(lookups == 2)
            } else {
                #expect(model.regionShortcut == saved[0])
                #expect(model.windowShortcut == saved[1])
                #expect(AppModel.loadShortcut("regionShortcut", defaults: defaults) == saved[0])
                #expect(AppModel.loadShortcut("windowShortcut", defaults: defaults) == saved[1])
                #expect(lookups == 0)
            }
            #expect(model.shortcutProblems.isEmpty)
            #expect(backend.held.values.contains(model.regionShortcut))
            #expect(backend.held.values.contains(model.windowShortcut))
            manager.unregisterAll()
        }
    }
    @Test func aSavedBindingTakesPrecedenceOverTheOtherNewDefault() throws {
        for savedIsWindow in [false, true] {
            let suite = "PartialHotKeyUpgradeTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
            let savedKey = savedIsWindow ? "windowShortcut" : "regionShortcut"
            let unsavedKey = savedIsWindow ? "regionShortcut" : "windowShortcut"
            let savedID: UInt32 = savedIsWindow ? 2 : 1
            let defaultID: UInt32 = savedIsWindow ? 1 : 2
            let saved = savedIsWindow ? Shortcut.region : Shortcut.window
            let originalPreference = try JSONEncoder().encode(saved)
            defaults.set(originalPreference, forKey: savedKey)
            let backend = FakeHotKeyBackend()
            let manager = HotKeyManager(backend: backend, systemShortcuts: { [] })
            let model = AppModel(defaults: defaults, historyDirectory: directory,
                                 hotkeyManager: manager, presentsWindows: false)
            defer { manager.unregisterAll() }
            #expect(manager.isRegistered(savedID))
            #expect(!manager.isRegistered(defaultID))
            #expect(model.shortcutProblems[savedID] == nil)
            #expect(model.shortcutProblems[defaultID] != nil)
            #expect(model.regionShortcut == model.windowShortcut)
            #expect(defaults.data(forKey: savedKey) == originalPreference)
            #expect(defaults.object(forKey: unsavedKey) == nil)
            let savedToken = try #require(backend.held.first(where: { $0.value == saved })?.key)
            model.findAvailableShortcuts()
            #expect(model.shortcutProblems.isEmpty)
            #expect(manager.isRegistered(1) && manager.isRegistered(2))
            #expect(model.regionShortcut != model.windowShortcut)
            #expect((savedIsWindow ? model.windowShortcut : model.regionShortcut) == saved)
            #expect(backend.held[savedToken] == saved)
            #expect(defaults.data(forKey: savedKey) == originalPreference)
            #expect(AppModel.loadShortcut(unsavedKey, defaults: defaults) == (savedIsWindow ? model.regionShortcut : model.windowShortcut))
        }
    }
    @Test func letterResolutionHandlesAZERTYAndCommandSpecificLayouts() {
        let commandControl = UInt32(cmdKey | controlKey)
        let us: [UInt16: String] = [15: "r", 13: "w"]
        let french: [UInt16: String] = [15: "r", 6: "w", 13: "z"]
        let dvorak: [UInt16: String] = [31: "r", 43: "w"]
        #expect(ShortcutKeyResolver.key(for: "W", modifiers: commandControl, translate: { key, _ in us[key] }) == 13)
        #expect(ShortcutKeyResolver.key(for: "w", modifiers: commandControl, translate: { key, _ in french[key] }) == 6)
        var observedModifiers = Set<UInt32>()
        let translate: (UInt16, UInt32) -> String? = { key, flags in
            observedModifiers.insert(flags)
            return (flags == UInt32(cmdKey) ? us : dvorak)[key]
        }
        #expect(ShortcutKeyResolver.key(for: "R", modifiers: commandControl | UInt32(optionKey | shiftKey), translate: translate) == 15)
        #expect(ShortcutKeyResolver.key(for: "W", modifiers: commandControl, translate: translate) == 13)
        #expect(ShortcutKeyResolver.key(for: "W", modifiers: UInt32(controlKey | shiftKey), translate: translate) == 43)
        #expect(observedModifiers == [0, UInt32(cmdKey)])
        #expect(ShortcutKeyResolver.key(for: "WR", modifiers: commandControl, translate: translate) == nil)
        #expect(ShortcutKeyResolver.key(for: "W", modifiers: commandControl, translate: { _, _ in "wr" }) == nil)
        #expect(ShortcutKeyResolver.key(for: "W", modifiers: commandControl, layoutData: Data(), keyboardType: 40) == nil)
        let fallback = Shortcut.captureDefault(window: true, resolve: { _, _ in nil })
        #expect(fallback.key == UInt32(kVK_ANSI_W))
        #expect(fallback.label.contains(String(fallback.key)))
        #expect(!fallback.label.hasSuffix("W"))
    }
    @Test func appDefaultsAndAlternativeKeysUseTheSuppliedLayout() throws {
        let suite = "LayoutHotKeyTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        // The test layout changes letter positions when Command is held.
        let resolve: (String, UInt32) -> UInt32? = { letter, flags in
            if flags & UInt32(cmdKey) != 0 { return letter == "R" ? 15 : 6 }
            return letter == "R" ? 31 : 43
        }
        let backend = FakeHotKeyBackend()
        backend.unavailable = [UInt32(cmdKey | controlKey), UInt32(cmdKey | controlKey | shiftKey), UInt32(cmdKey | optionKey)].map {
            Shortcut.captureDefault(window: false, modifiers: $0, resolve: resolve)
        }
        let manager = HotKeyManager(backend: backend, systemShortcuts: { [] })
        defer { manager.unregisterAll() }
        let model = AppModel(defaults: defaults, historyDirectory: directory,
                             hotkeyManager: manager, presentsWindows: false, shortcutKeyResolver: resolve)
        #expect(model.regionShortcut.key == 15)
        #expect(model.windowShortcut.key == 6)
        #expect(model.windowShortcut.label == "⌃⌘W")
        #expect(model.shortcutProblems[1] != nil && model.shortcutProblems[2] == nil)
        model.findAvailableShortcuts()
        #expect(model.regionShortcut.key == 31)
        #expect(model.regionShortcut.modifiers == UInt32(controlKey | shiftKey))
        #expect(model.regionShortcut.label == "⌃⇧R")
        #expect(model.windowShortcut.key == 6)
        #expect(model.shortcutProblems.isEmpty)
    }
    @Test func installedUSAndFrenchLayoutsResolveWithoutSelectingThem() throws {
        func currentSourceID() -> String? {
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
        }
        let before = try #require(currentSourceID())
        defer { #expect(currentSourceID() == before) }
        for (identifier, windowKey) in [("com.apple.keylayout.US", UInt32(kVK_ANSI_W)),
                                        ("com.apple.keylayout.French", UInt32(kVK_ANSI_Z))] {
            let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
            let sources = try #require(TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])
            let source = try #require(sources.first, "Required installed Apple keyboard layout: \(identifier)")
            let data = try #require(ShortcutKeyResolver.layoutData(from: source))
            #expect(ShortcutKeyResolver.key(for: "R", modifiers: UInt32(cmdKey | controlKey), layoutData: data, keyboardType: 40) == UInt32(kVK_ANSI_R))
            #expect(ShortcutKeyResolver.key(for: "W", modifiers: UInt32(cmdKey | controlKey), layoutData: data, keyboardType: 40) == windowKey)
        }
    }
    @Test func statusSymbolExistsOnThisMac() {
        #expect(NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil) != nil)
    }
}
