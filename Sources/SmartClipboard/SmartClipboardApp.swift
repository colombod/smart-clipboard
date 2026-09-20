import SwiftUI

@main struct SmartClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.model.showSettings(tab: "shortcuts") }.keyboardShortcut(",")
                }
            }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) lazy var model = AppModel()
    private var statusItem: NSStatusItem?
    private var started = false
    private let readinessItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A development/download copy must not compete with the already-running app.
        let current = NSRunningApplication.current
        if let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter({ $0.processIdentifier != current.processIdentifier && !$0.isTerminated && ($0.launchDate ?? .distantPast) <= (current.launchDate ?? .distantFuture) })
            .sorted(by: { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }).first,
           let url = existing.bundleURL {
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        started = true
        installStatusItem()
        model.refreshReadiness()
        if CommandLine.arguments.contains("--show") || !UserDefaults.standard.bool(forKey: "hasLaunched") || !model.captureReady {
            model.showPanel()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "SmartClipboard.StatusItem"
        item.behavior = []
        item.isVisible = true
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Smart Clipboard")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = " Clip"
            button.toolTip = "Smart Clipboard — capture, history and settings"
            button.setAccessibilityLabel("Smart Clipboard")
        }
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(readinessItem)
        menu.addItem(.separator())
        add("Capture Region…", action: #selector(captureRegion), to: menu)
        add("Capture Window…", action: #selector(captureWindow), to: menu)
        menu.addItem(.separator())
        add("Open Clipboard…", action: #selector(openClipboard), to: menu)
        add("History…", action: #selector(openHistory), to: menu)
        add("Import Image…", action: #selector(importImage), to: menu)
        menu.addItem(.separator())
        add("Settings & Status…", action: #selector(openSettings), to: menu)
        add("Quit Smart Clipboard", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
        model.menuBarInstalled = item.button != nil
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
    }
    func menuWillOpen(_ menu: NSMenu) {
        model.refreshReadiness()
        readinessItem.title = model.captureReady ? "Running · Ready to capture" : "Running · Setup needs attention"
    }
    func applicationDidBecomeActive(_ notification: Notification) { if started { model.refreshReadiness() } }
    func applicationWillTerminate(_ notification: Notification) { if started { model.persistCurrentOutput(); model.cancel() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if started { statusItem?.isVisible = true; model.showPanel() }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc private func captureRegion() { model.capture() }
    @objc private func captureWindow() { model.capture(window: true) }
    @objc private func openClipboard() { model.showPanel() }
    @objc private func openHistory() { model.showHistory() }
    @objc private func importImage() { model.importImage() }
    @objc private func openSettings() { model.showSettings(tab: "shortcuts") }
    @objc private func quit() { NSApp.terminate(nil) }
}
