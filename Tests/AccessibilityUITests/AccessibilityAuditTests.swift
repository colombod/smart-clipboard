import XCTest

/// Native audits of the compile-time isolated synthetic app, not production capture acceptance.
final class AccessibilityAuditTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true // Preserve all audit findings instead of stopping at the first.
    }

    @MainActor func test01QuietStartupAndRealSettingsNavigation() throws {
        let app = try application()
        app.launch()
        defer { app.terminate() }
        let unexpectedWindow = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count > 0 }, object: nil)
        unexpectedWindow.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedWindow], timeout: 2), .completed, "Startup must stay in the menu bar.")
        attach(app.debugDescription, name: "quiet-startup-accessibility-tree")

        app.activate()
        app.typeKey(",", modifierFlags: .command)
        let settings = try visibleWindow("Smart Clipboard Settings", in: app)
        for (tab, evidence) in [
            ("General", "Preferred format"), ("Connection", "Test image processing"),
            ("Shortcuts", "Capture shortcuts"), ("History", "Capture history"),
            ("About", "Third-party notices")
        ] {
            let candidates = [settings.radioButtons[tab], settings.tabs[tab], settings.buttons[tab]]
            guard let control = candidates.first(where: { $0.exists && $0.isHittable }) else {
                attach(app.debugDescription, name: "missing-\(tab)-tab")
                throw HarnessError("The native \(tab) tab is not reachable.")
            }
            control.click()
            let content = settings.descendants(matching: .any).matching(identifier: evidence).firstMatch
            guard content.waitForExistence(timeout: 5) else {
                attach(app.debugDescription, name: "unselected-\(tab)-tab")
                throw HarnessError("Selecting \(tab) did not expose its expected content: \(evidence).")
            }
        }
        attach(settings.screenshot(), name: "settings-after-real-navigation")
        app.typeKey("w", modifierFlags: .command)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !settings.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed, "Command-W must close Settings.")
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground, "Closing Settings must keep the menu-bar app running.")
        attach(app.debugDescription, name: "settings-closed-by-keyboard")
    }

    @MainActor func testSettingsGeneral() throws { try audit(screen: "settings-general", title: "Smart Clipboard Settings") }
    @MainActor func testSettingsConnection() throws { try audit(screen: "settings-connection", title: "Smart Clipboard Settings") }
    @MainActor func testSettingsConnectionOpenAI() throws { try audit(screen: "settings-connection", title: "Smart Clipboard Settings", provider: "openai") }
    @MainActor func testSettingsConnectionCodex() throws { try audit(screen: "settings-connection", title: "Smart Clipboard Settings", provider: "codex") }
    @MainActor func testSettingsConnectionAnthropic() throws { try audit(screen: "settings-connection", title: "Smart Clipboard Settings", provider: "anthropic") }
    @MainActor func testSettingsConnectionGoogleGemini() throws { try audit(screen: "settings-connection", title: "Smart Clipboard Settings", provider: "google") }
    @MainActor func testSettingsConnectionPerplexity() throws { try audit(screen: "settings-connection", title: "Smart Clipboard Settings", provider: "perplexity") }
    @MainActor func testSettingsConnectionOMLX() throws { try audit(screen: "settings-connection", title: "Smart Clipboard Settings", provider: "omlx") }
    @MainActor func testSettingsShortcuts() throws { try audit(screen: "settings-shortcuts", title: "Smart Clipboard Settings") }
    @MainActor func testSettingsHistory() throws { try audit(screen: "settings-history", title: "Smart Clipboard Settings") }
    @MainActor func testSettingsAbout() throws { try audit(screen: "settings-about", title: "Smart Clipboard Settings") }
    @MainActor func testEditorEmpty() throws { try audit(screen: "editor", title: "Smart Clipboard") }
    @MainActor func testEditorPopulated() throws { try audit(screen: "editor", title: "Smart Clipboard", populated: true) }
    @MainActor func testHistoryEmpty() throws { try audit(screen: "history", title: "Capture History") }
    @MainActor func testHistoryPopulated() throws { try audit(screen: "history", title: "Capture History", populated: true) }

    @MainActor private func application() throws -> XCUIApplication {
        guard let path = ProcessInfo.processInfo.environment["SMART_CLIPBOARD_AUDIT_APP_PATH"],
              let bundle = Bundle(path: path), bundle.bundleIdentifier == "com.smartclipboard.accessibility-audit" else {
            throw HarnessError("The runner requires the separate com.smartclipboard.accessibility-audit bundle.")
        }
        return XCUIApplication(url: URL(fileURLWithPath: path))
    }

    @MainActor private func visibleWindow(_ title: String, in app: XCUIApplication) throws -> XCUIElement {
        let window = app.windows[title]
        guard window.waitForExistence(timeout: 15), window.isHittable else {
            attach(app.debugDescription, name: "missing-window-accessibility-tree")
            throw HarnessError("The expected native window did not become available: \(title).")
        }
        return window
    }

    @MainActor private func audit(screen: String, title: String, populated: Bool = false, provider: String? = nil) throws {
        let app = try application()
        app.launchArguments = ["--audit-screen", screen] + (populated ? ["--audit-populated"] : [])
        if let provider { app.launchArguments += ["--audit-provider", provider] }
        app.launch()
        defer { app.terminate() }
        let window = try visibleWindow(title, in: app)
        let expectedContent: String
        switch screen {
        case "settings-general": expectedContent = "Preferred format"
        case "settings-connection": expectedContent = "AI connection"
        case "settings-shortcuts": expectedContent = "Capture shortcuts"
        case "settings-history": expectedContent = "Capture history"
        case "settings-about": expectedContent = "Third-party notices"
        case "editor": expectedContent = populated ? "Converted result" : "From your screen to your next idea."
        case "history": expectedContent = populated ? "# Accessibility sample" : "No saved captures yet"
        default: throw HarnessError("Unsupported audit screen.")
        }
        // macOS exposes static text as value, while controls use label. SwiftUI
        // also combines empty-state and history text into larger native elements.
        let labelledContent = window.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", expectedContent)).firstMatch
        let textContent = window.staticTexts
            .matching(NSPredicate(format: "value CONTAINS %@", expectedContent)).firstMatch
        let contentAppeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            labelledContent.exists || textContent.exists
        }, object: nil)
        guard XCTWaiter.wait(for: [contentAppeared], timeout: 5) == .completed else {
            attach(app.debugDescription, name: "unexpected-\(screen)-state")
            throw HarnessError("The requested \(screen) state was not exposed in the native accessibility tree.")
        }
        if screen == "settings-connection" {
            let titles = ["openai": "OpenAI", "codex": "ChatGPT via Codex", "anthropic": "Anthropic",
                          "google": "Google Gemini", "perplexity": "Perplexity", "omlx": "Local / oMLX"]
            let requested = provider ?? "omlx"
            guard let title = titles[requested],
                  window.popUpButtons.matching(NSPredicate(format: "value == %@", title)).firstMatch.waitForExistence(timeout: 5) else {
                attach(app.debugDescription, name: "unexpected-connection-\(requested)")
                throw HarnessError("The Provider picker did not select the requested \(requested) route.")
            }
        }
        let name = screen + (provider.map { "-" + $0 } ?? "") + (populated ? "-populated" : "-empty")
        attach(window.screenshot(), name: name + "-window")
        attach(app.debugDescription, name: name + "-accessibility-tree")
        var report = AuditReport(screen: screen, populated: populated, provider: provider)
        defer {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
                attachment.name = name + "-audit.json"
                attachment.lifetime = .keepAlways
                add(attachment)
            } catch { XCTFail("Could not attach the audit report: \(error.localizedDescription)") }
        }
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                report.findings.append(AuditFinding(type: issue.auditType.rawValue, summary: issue.compactDescription,
                                                    details: issue.detailedDescription, element: issue.element?.debugDescription))
                return false // Never suppress a finding: XCTest must record each one as a failure.
            }
            report.completed = true
        } catch {
            report.executionError = error.localizedDescription
            throw error
        }
        XCTAssertTrue(report.findings.isEmpty, "The native audit reported \(report.findings.count) findings; see the attached JSON and Xcode issues.")
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct HarnessError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private struct AuditFinding: Encodable {
    let type: UInt64
    let summary: String
    let details: String
    let element: String?
}

private struct AuditReport: Encodable {
    let screen: String
    let populated: Bool
    let provider: String?
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let scope = "All native macOS XCTest accessibility audit categories, with synthetic app data. This is not production capture acceptance or a manual VoiceOver test. macOS does not expose the iOS Dynamic Type audit category."
    var completed = false
    var executionError: String?
    var findings: [AuditFinding] = []
}
