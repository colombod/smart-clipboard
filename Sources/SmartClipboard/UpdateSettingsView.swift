import SwiftUI
import ClipboardCore

struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Updates")).font(.headline)
            Toggle(L10n.text("Check for updates daily"), isOn: Binding(get: { updates.automaticallyChecks }, set: updates.setAutomaticallyChecks))
                .disabled(!updates.canChangePreferences)
            Picker(L10n.text("Releases"), selection: Binding(get: { updates.channel }, set: updates.setChannel)) {
                ForEach(UpdateChannel.allCases) { Text($0.title).tag($0) }
            }.disabled(!updates.canChangePreferences)
            Text(L10n.text("Background checks only add an update notice to the Clip menu. You choose when to download and install. Preview releases may have unfinished features."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(updates.menuTitle) { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
                if updates.activityInProgress {
                    Text(L10n.text("Available when the current task finishes.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(updates.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 440, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("App updates"))
    }
}
