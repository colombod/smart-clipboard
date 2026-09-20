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
    @Test func statusSymbolExistsOnThisMac() {
        #expect(NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil) != nil)
    }
}
