import AppKit
import Testing
@testable import SmartClipboard

struct ShortcutRecorderAccessibilityTests {
    @Test func escapeCancelsAndTabOrArrowNavigationIsNotRecorded() {
        #expect(ShortcutRecorderInput.action(keyCode: 53, modifiers: [], voiceOverEnabled: false) == .cancel)
        for key: UInt16 in [48, 123, 124, 125, 126] {
            for flags: NSEvent.ModifierFlags in [[], [.shift]] {
                #expect(ShortcutRecorderInput.action(keyCode: key, modifiers: flags, voiceOverEnabled: false) == .navigate)
            }
        }
        #expect(ShortcutRecorderInput.action(keyCode: 48, modifiers: [.control], voiceOverEnabled: false) == .record)
    }

    @Test func closeAndQuitCommandsRemainAvailableWhileRecording() {
        for character in ["w", "q", "W", "Q"] {
            #expect(ShortcutRecorderInput.action(keyCode: 0, modifiers: [.command], characters: character, voiceOverEnabled: false) == .navigate)
        }
        #expect(ShortcutRecorderInput.action(keyCode: 20, modifiers: [.command, .shift, .option], characters: "3", voiceOverEnabled: false) == .record)
    }

    @Test func voiceOverControlOptionCommandsPassThroughInsteadOfBecomingShortcuts() {
        for key: UInt16 in [49, 123, 124] {
            #expect(ShortcutRecorderInput.action(keyCode: key, modifiers: [.control, .option], voiceOverEnabled: true) == .assistiveNavigation)
            #expect(ShortcutRecorderInput.action(keyCode: key, modifiers: [.control, .option], voiceOverEnabled: false) == .record)
        }
    }
}
