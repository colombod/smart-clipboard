import AppKit
import ClipboardCore

/// Only predefined operation metadata enters accessibility status. Captured text,
/// conversion output, file names, and provider error messages are never retained.
struct AccessibilityStatusSnapshot: Equatable {
    enum Notice: Equatable {
        case none, imageCopied, resultCopied(OutputFormat), captureCancelled, conversionCancelled

        var copied: Bool {
            switch self {
            case .imageCopied, .resultCopied: return true
            default: return false
            }
        }

        var message: String {
            switch self {
            case .none: return ""
            case .imageCopied: return L10n.text("Image copied.")
            case .resultCopied(let format): return L10n.text("\(format.title) copied.")
            case .captureCancelled: return L10n.text("Capture cancelled.")
            case .conversionCancelled: return L10n.text("Conversion cancelled.")
            }
        }

        var announcement: String? {
            switch self {
            case .none: return nil
            case .imageCopied: return L10n.text("Image copied. Ready to paste.")
            case .resultCopied(let format): return L10n.text("\(format.title) copied. Ready to paste.")
            case .captureCancelled: return L10n.text("Capture cancelled.")
            case .conversionCancelled: return L10n.text("Conversion cancelled.")
            }
        }
    }

    static var failureMessage: String { L10n.text("Smart Clipboard needs attention. Open Clipboard from the menu bar for details.") }
    let capturing: Bool
    let processing: Bool
    let failed: Bool
    let notice: Notice

    init(capturing: Bool = false, processing: Bool = false, failed: Bool = false, notice: Notice = .none) {
        self.capturing = capturing
        self.processing = processing
        self.failed = failed
        self.notice = notice
    }

    func accessibilityValue(ready: Bool, preferredFormat: OutputFormat) -> String {
        if processing { return L10n.text("Processing your capture.") }
        if capturing { return L10n.text("Select a region or window. Press Escape to cancel.") }
        if failed { return Self.failureMessage }
        if let announcement = notice.announcement { return announcement }
        return ready ? L10n.text("Ready. Preferred format: \(preferredFormat.title).") : L10n.text("Setup needs attention.")
    }
}

@MainActor final class AccessibilityStatusAnnouncer {
    private let isVoiceOverEnabled: () -> Bool
    private let post: (String) -> Void
    private var previous: AccessibilityStatusSnapshot?
    private var operationHasOutcome = false

    // Both dependencies are required so tests never post real announcements.
    init(isVoiceOverEnabled: @escaping () -> Bool, post: @escaping (String) -> Void) {
        self.isVoiceOverEnabled = isVoiceOverEnabled
        self.post = post
    }

    static func live() -> AccessibilityStatusAnnouncer {
        AccessibilityStatusAnnouncer(isVoiceOverEnabled: { NSWorkspace.shared.isVoiceOverEnabled }) { message in
            guard NSWorkspace.shared.isVoiceOverEnabled else { return }
            // The application element also works when this menu-bar app has no
            // key window. Posting an announcement does not activate a window.
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                 userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    func observe(_ state: AccessibilityStatusSnapshot) {
        let old = previous
        // Consume transitions even with VoiceOver off; never replay stale results.
        previous = state
        guard let old, old != state else { return }
        let message: String?
        if state.failed && !old.failed {
            operationHasOutcome = true
            message = AccessibilityStatusSnapshot.failureMessage
        } else if state.notice != old.notice, let notice = state.notice.announcement {
            operationHasOutcome = true
            message = notice
        } else if state.processing && !old.processing {
            operationHasOutcome = false
            message = L10n.text("Processing your capture.")
        } else if state.capturing && !old.capturing {
            operationHasOutcome = false
            message = L10n.text("Select a region or window. Press Escape to cancel.")
        } else if old.processing && !state.processing && !state.failed && !operationHasOutcome {
            operationHasOutcome = true
            message = L10n.text("Conversion complete.")
        } else { message = nil }
        if let message, isVoiceOverEnabled() { post(message) }
    }
}
