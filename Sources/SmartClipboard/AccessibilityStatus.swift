import AppKit
import ClipboardCore

/// Only predefined operation metadata enters accessibility status. Captured text,
/// conversion output, file names, and provider error messages are never retained.
struct AccessibilityStatusSnapshot: Equatable {
    enum Notice: Equatable {
        case none, imageCopied, resultCopied(OutputFormat), captureCancelled, conversionCancelled

        init(_ notice: String) {
            switch notice {
            case "Image copied.": self = .imageCopied
            case "Capture cancelled.": self = .captureCancelled
            case "Conversion cancelled.": self = .conversionCancelled
            default:
                if let format = OutputFormat.allCases.first(where: { notice == "\($0.title) copied." }) {
                    self = .resultCopied(format)
                } else { self = .none }
            }
        }

        var announcement: String? {
            switch self {
            case .none: return nil
            case .imageCopied: return "Image copied. Ready to paste."
            case .resultCopied(let format): return "\(format.title) copied. Ready to paste."
            case .captureCancelled: return "Capture cancelled."
            case .conversionCancelled: return "Conversion cancelled."
            }
        }
    }

    static let failureMessage = "Smart Clipboard needs attention. Open Clipboard from the menu bar for details."
    let capturing: Bool
    let processing: Bool
    let failed: Bool
    let notice: Notice

    init(capturing: Bool = false, processing: Bool = false, failed: Bool = false, notice: String = "") {
        self.capturing = capturing
        self.processing = processing
        self.failed = failed
        self.notice = Notice(notice)
    }

    func accessibilityValue(ready: Bool, preferredFormat: OutputFormat) -> String {
        if processing { return "Processing your capture." }
        if capturing { return "Select a region or window. Press Escape to cancel." }
        if failed { return Self.failureMessage }
        if let announcement = notice.announcement { return announcement }
        return ready ? "Ready. Preferred format: \(preferredFormat.title)." : "Setup needs attention."
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
            message = "Processing your capture."
        } else if state.capturing && !old.capturing {
            operationHasOutcome = false
            message = "Select a region or window. Press Escape to cancel."
        } else if old.processing && !state.processing && !state.failed && !operationHasOutcome {
            operationHasOutcome = true
            message = "Conversion complete."
        } else { message = nil }
        if let message, isVoiceOverEnabled() { post(message) }
    }
}
