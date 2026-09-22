import SwiftUI
import Combine

// An AppKit lifecycle avoids SwiftUI automatically presenting a Settings scene.
@main enum SmartClipboardApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    #if ACCESSIBILITY_AUDIT
    private lazy var auditHarness = AccessibilityAuditHarness()
    private(set) lazy var model = auditHarness.model
    private lazy var accessibilityAnnouncements = auditHarness.announcer
    #else
    private(set) lazy var model = AppModel()
    private let accessibilityAnnouncements = AccessibilityStatusAnnouncer.live()
    #endif
    private var statusItem: NSStatusItem?
    private var started = false
    private var statusSubscription: AnyCancellable?
    private var accessibilitySubscription: AnyCancellable?
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
        installMainMenu()
        #if ACCESSIBILITY_AUDIT
        auditHarness.launch(arguments: CommandLine.arguments)
        #else
        if CommandLine.arguments.contains("--show") { model.showPanel() }
        #endif
    }
    private func installMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        add("About Smart Clipboard…", action: #selector(openAbout), to: appMenu)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Smart Clipboard", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; appMenu.addItem(quit)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); bar.addItem(fileItem)
        let file = NSMenu(title: "File"); fileItem.submenu = file
        // A nil target uses the responder chain to close only the current window.
        file.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); bar.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key))
        }
        NSApp.mainMenu = bar
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
        add("Cancel Capture / Conversion", action: #selector(cancelOperation), to: menu)
        add("Settings & Status…", action: #selector(openSettings), to: menu)
        add("About Smart Clipboard…", action: #selector(openAbout), to: menu)
        menu.addItem(.separator())
        add("Quit Smart Clipboard", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
        model.menuBarInstalled = item.button != nil
        statusSubscription = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        // Read the publishers' new values synchronously: a quick image capture
        // can start and copy before the deferred visual status update runs.
        accessibilitySubscription = Publishers.CombineLatest4(model.$capturing, model.$busy,
                                                               model.$error.map { $0 != nil }, model.$notice)
            .sink { [weak self] state in
                self?.accessibilityAnnouncements.observe(AccessibilityStatusSnapshot(capturing: state.0, processing: state.1,
                                                                                     failed: state.2, notice: state.3))
            }
        updateStatus()
    }
    private func updateStatus() {
        let message: String
        let suffix: String
        if model.capturing { message = "Select a region or window"; suffix = " …" }
        else if model.busy { message = "Converting your capture…"; suffix = " …" }
        else if let error = model.error { message = error; suffix = " !" }
        else if model.notice.contains("copied") { message = model.notice + " Ready to paste."; suffix = " ✓" }
        else { message = model.captureReady ? "Ready · " + model.defaultFormat.title : "Setup needs attention"; suffix = "" }
        statusItem?.button?.title = " Clip" + suffix
        statusItem?.button?.toolTip = message
        let accessibleStatus = AccessibilityStatusSnapshot(capturing: model.capturing, processing: model.busy,
                                                            failed: model.error != nil, notice: model.notice)
        statusItem?.button?.setAccessibilityValue(accessibleStatus.accessibilityValue(ready: model.captureReady,
                                                                                     preferredFormat: model.defaultFormat))
        readinessItem.title = message
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
    }
    func menuWillOpen(_ menu: NSMenu) {
        model.refreshReadiness()
        updateStatus()
    }
    func applicationDidBecomeActive(_ notification: Notification) { if started { model.refreshReadiness() } }
    func applicationWillTerminate(_ notification: Notification) {
        if started {
            model.persistCurrentOutput(); model.cancel()
            #if ACCESSIBILITY_AUDIT
            auditHarness.cleanup()
            #endif
        }
    }
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
    @objc private func openSettings() { model.showSettings(tab: "general") }
    @objc private func openAbout() { model.showSettings(tab: "about") }
    @objc private func cancelOperation() { model.cancel() }
    @objc private func quit() { NSApp.terminate(nil) }
}
