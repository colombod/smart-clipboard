import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Updates").font(.headline)
            Toggle("Check for updates daily", isOn: Binding(get: { updates.automaticallyChecks }, set: updates.setAutomaticallyChecks))
                .disabled(!updates.canChangePreferences)
            Picker("Releases", selection: Binding(get: { updates.channel }, set: updates.setChannel)) {
                ForEach(UpdateChannel.allCases) { Text($0.title).tag($0) }
            }.disabled(!updates.canChangePreferences)
            Text("Background checks only add an update notice to the Clip menu. You choose when to download and install. Preview releases may have unfinished features.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(updates.menuTitle) { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
                if updates.activityInProgress {
                    Text("Available when the current task finishes.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(updates.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 440, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App updates")
    }
}
