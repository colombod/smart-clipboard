import AppKit
import ClipboardCore

// The capture action owns permission negotiation; the screenshot command never runs after denial.
@MainActor struct CaptureClient {
    var hasAccess: () -> Bool = { CGPreflightScreenCaptureAccess() }
    var requestAccess: () -> Bool = { CGRequestScreenCaptureAccess() }
    var takeImage: (Bool) async throws -> Data? = { try await CaptureService.capture(window: $0) }

    func capture(window: Bool, willBegin: () -> Void) async throws -> Data? {
        guard hasAccess() || requestAccess() || hasAccess() else {
            throw ClipError.message(L10n.text("macOS has not allowed Screen Recording for Smart Clipboard. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app. If the switch is already on after an app update, turn it off and on again to refresh permission. Your capture has not started."))
        }
        try Task.checkCancellation()
        willBegin()
        // Let our windows disappear before the native screenshot selector opens.
        try await Task.sleep(for: .milliseconds(250))
        return try await takeImage(window)
    }
}
