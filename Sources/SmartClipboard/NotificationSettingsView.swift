import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var notifications: CaptureNotifications

    var body: some View {
        Section("Capture notifications") {
            Text(notifications.status).font(.callout).accessibilityLabel("Notification status: \(notifications.status)")
            HStack {
                if notifications.enabled && notifications.authorization != .notDetermined {
                    Button("Turn off notifications") { notifications.disable() }
                } else if notifications.authorization != .denied {
                    Button("Enable notifications") { Task { await notifications.enableFromSettings() } }
                }
                Button("Open notification settings") { notifications.openSystemSettings() }
                if notifications.requestingPermission {
                    ProgressView().controlSize(.small).accessibilityLabel("Waiting for notification permission")
                }
            }
            .disabled(!notifications.isAvailable || notifications.requestingPermission)
            if let message = notifications.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Toggle("When a capture is ready to paste", isOn: $notifications.notifyOnSuccess)
                .disabled(!notifications.isAvailable || notifications.requestingPermission)
            Toggle("When capture or conversion fails", isOn: $notifications.notifyOnFailure)
                .disabled(!notifications.isAvailable || notifications.requestingPermission)
            Toggle("Play a notification sound", isOn: $notifications.playsSound)
                .disabled(!notifications.isAvailable || notifications.requestingPermission)
            if notifications.playsSound && notifications.authorization.permitsDelivery && !notifications.soundEnabled {
                Text("Sounds are disabled in macOS notification settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Notifications show only the output format and status, never capture text or error details. They open Smart Clipboard only when clicked. Focus modes and macOS settings may silence alerts; the Clip menu still shows status.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .tint(accent)
        .task { await notifications.refreshAuthorization() }
    }
}
