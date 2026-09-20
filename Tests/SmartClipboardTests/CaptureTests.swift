import AppKit
import Testing
@testable import SmartClipboard

@MainActor struct CaptureTests {
    @Test func deniedPreflightRequestsPermissionAndContinuesSameCaptureWhenGranted() async throws {
        var requests = 0, selections: [Bool] = [], begins = 0
        let expected = Data([1, 2, 3])
        let client = CaptureClient(hasAccess: { false }, requestAccess: { requests += 1; return true }, takeImage: { window in selections.append(window); return expected })
        let result = try await client.capture(window: true) { begins += 1 }
        #expect(result == expected)
        #expect(requests == 1)
        #expect(selections == [true])
        #expect(begins == 1)
    }
    @Test func previouslyAllowedAccessDoesNotPromptAndPreservesRegionMode() async throws {
        var requests = 0, selections: [Bool] = []
        let client = CaptureClient(hasAccess: { true }, requestAccess: { requests += 1; return false }, takeImage: { selections.append($0); return nil })
        let result = try await client.capture(window: false) {}
        #expect(result == nil)
        #expect(requests == 0)
        #expect(selections == [false])
    }
    @Test func deniedPermissionNeverHidesWindowsOrStartsCapture() async {
        var requests = 0, began = false, captured = false
        let client = CaptureClient(hasAccess: { false }, requestAccess: { requests += 1; return false }, takeImage: { _ in captured = true; return nil })
        await #expect(throws: (any Error).self) { try await client.capture(window: false) { began = true } }
        #expect(requests == 1)
        #expect(!began)
        #expect(!captured)
    }
    @Test func permissionGrantedWhilePromptClosesIsRechecked() async throws {
        var allowed = false, captured = false
        let client = CaptureClient(hasAccess: { allowed }, requestAccess: { allowed = true; return false }, takeImage: { _ in captured = true; return nil })
        _ = try await client.capture(window: false) {}
        #expect(captured)
    }
    @Test func failedCommandWithNoImageIsNotSilentlyCancelled() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: (any Error).self) { try CaptureService.readCaptureResult(status: 1, output: "could not create image from display", destination: missing) }
        #expect(try CaptureService.readCaptureResult(status: 0, output: "", destination: missing) == nil)
    }
    @Test func invalidImageIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a PNG".utf8).write(to: url)
        #expect(throws: (any Error).self) { try CaptureService.readCaptureResult(status: 0, output: "", destination: url) }
    }
}
