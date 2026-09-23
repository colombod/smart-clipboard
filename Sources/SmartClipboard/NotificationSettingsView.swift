import SwiftUI
import ClipboardCore

struct NotificationSettingsView: View {
    @ObservedObject var notifications: CaptureNotifications

    var body: some View {
        Section(L10n.text("Capture notifications")) {
            Text(notifications.status).font(.callout).accessibilityLabel(L10n.text("Notification status: \(notifications.status)"))
            HStack {
                if notifications.enabled && notifications.authorization != .notDetermined {
                    Button(L10n.text("Turn off notifications")) { notifications.disable() }
                } else if notifications.authorization != .denied {
                    Button(L10n.text("Enable notifications")) { Task { await notifications.enableFromSettings() } }
                }
                Button(L10n.text("Open notification settings")) { notifications.openSystemSettings() }
                if notifications.requestingPermission {
                    ProgressView().controlSize(.small).accessibilityLabel(L10n.text("Waiting for notification permission"))
                }
            }
            .disabled(!notifications.isAvailable || notifications.requestingPermission)
            if let message = notifications.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Toggle(L10n.text("When a capture is ready to paste"), isOn: $notifications.notifyOnSuccess)
                .disabled(!notifications.isAvailable || notifications.requestingPermission)
            Toggle(L10n.text("When capture or conversion fails"), isOn: $notifications.notifyOnFailure)
                .disabled(!notifications.isAvailable || notifications.requestingPermission)
            Toggle(L10n.text("Play a notification sound"), isOn: $notifications.playsSound)
                .disabled(!notifications.isAvailable || notifications.requestingPermission)
            if notifications.playsSound && notifications.authorization.permitsDelivery && !notifications.soundEnabled {
                Text(L10n.text("Sounds are disabled in macOS notification settings."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("Notifications show only the output format and status, never capture text or error details. They open Smart Clipboard only when clicked. Focus modes and macOS settings may silence alerts; the Clip menu still shows status."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .tint(accent)
        .task { await notifications.refreshAuthorization() }
    }
}
