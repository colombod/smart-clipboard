import AppKit
import Testing
@testable import SmartClipboard

struct ServiceTests {
    @Test func processCapturesOutputAndExit() async throws {
        let (status, text) = try await ProcessRunner().run("/usr/bin/printf", ["fixture output"])
        #expect(status == 0)
        #expect(text == "fixture output")
    }
    @Test func missingExecutableFails() async {
        await #expect(throws: (any Error).self) { try await ProcessRunner().run("/nonexistent/clipboard-test", []) }
    }
    @Test func processTimeoutTerminates() async {
        let start = Date()
        await #expect(throws: (any Error).self) { try await ProcessRunner().run("/bin/sleep", ["10"], timeout: 0.1) }
        #expect(Date().timeIntervalSince(start) < 3)
    }
    @Test func cancelledProcessReturnsPromptly() async throws {
        let runner = ProcessRunner()
        let task = Task { try await runner.run("/bin/sleep", ["10"]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let start = Date()
        do {
            _ = try await task.value
            // Process exit can race with cancellation; the caller also checks Task cancellation.
        } catch { #expect(error is CancellationError) }
        #expect(Date().timeIntervalSince(start) < 3)
    }
    @Test @MainActor func localOCRReadsGeneratedFixture() async throws {
        let image = NSImage(size: NSSize(width: 900, height: 160))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 900, height: 160).fill()
        ("Smart Clipboard 123" as NSString).draw(at: NSPoint(x: 40, y: 55), withAttributes: [.font: NSFont.systemFont(ofSize: 54), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let text = try await CaptureService.recognize(png)
        #expect(text.contains("Smart Clipboard 123"))
    }
}
