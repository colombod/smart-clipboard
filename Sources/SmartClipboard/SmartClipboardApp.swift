import SwiftUI

@main struct SmartClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("Smart Clipboard", systemImage: "crop.viewfinder") {
            Button("Capture Region…") { delegate.model.capture() }
            Button("Capture Window…") { delegate.model.capture(window: true) }
            Divider()
            Button("Open Clipboard…") { delegate.model.showPanel() }
            Button("Import Image…") { delegate.model.importImage() }
            Divider()
            Button("Settings…") { delegate.model.showSettings() }.keyboardShortcut(",")
            Button("Quit Smart Clipboard") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--show") || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            model.showPanel()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
