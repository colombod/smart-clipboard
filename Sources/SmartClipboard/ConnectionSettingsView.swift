import SwiftUI
import ClipboardCore

private typealias ConnectionViewState<Value> = SwiftUI.State<Value>

struct ConnectionSettingsView: View {
    @ObservedObject var store: ConnectionStore
    @ConnectionViewState<String> private var newKey = ""
    @ConnectionViewState<String> private var message = ""
    @ConnectionViewState<UInt64?> private var messageRevision = nil
    @ConnectionViewState<Bool> private var working = false
    @ConnectionViewState<Task<Void, Never>?> private var operation = nil
    @ConnectionViewState<[ProviderModel]> private var models = []
    @ConnectionViewState<UInt64?> private var modelsRevision = nil

    var body: some View {
        Form {
            Section("AI connection") {
                Picker("Provider", selection: $store.activeProvider) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                }
                Text("Captures use this connection. Auto detect chooses the output format; it keeps your selected provider.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.activeProvider == .omlx {
                    TextField("Server address", text: field(\.endpoint), prompt: Text("http://127.0.0.1:8000/v1"))
                    Text("Connect to an already running oMLX server with an image-capable model. Screenshots go to this address, which may be on this Mac or your local network.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.activeProvider == .codex {
                    TextField("Codex executable", text: field(\.executable), prompt: Text("Auto-detect"))
                    Text("Use your ChatGPT plan’s Codex access through the official Codex CLI. Credentials stay with Codex. Subscription limits and workspace policies apply.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Sign in with ChatGPT") { signIn() }.disabled(working)
                    Link("Install / update Codex CLI ↗", destination: URL(string: "https://developers.openai.com/codex/cli")!)
                } else {
                    keyControls
                }
            }
            Section("Image processing") {
                TextField(store.activeProvider == .codex ? "Model (optional)" : "Vision model", text: field(\.model), prompt: Text(store.activeProvider == .codex ? "Codex default" : "Enter an image-capable model"))
                if store.activeProvider != .codex {
                    HStack {
                        Button("Refresh models") { refreshModels() }.disabled(working || hasUnsavedKey)
                        if modelsRevision == store.revision, !models.isEmpty {
                            Menu("Choose a listed model") {
                                ForEach(models) { model in
                                    Button(model.id + (model.imageInput == nil ? " (image support unverified)" : "")) {
                                        var profile = store.activeProfile
                                        profile.model = model.id
                                        store.update(profile)
                                    }
                                }
                            }
                        }
                    }
                    Text("Models known to accept only text are hidden. You can enter a model manually; a model list alone does not confirm image support.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Test image processing sends a small synthetic image with sample text through this connection. It does not use your captures. Provider charges or subscription usage may apply.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Test image processing") { testImageProcessing() }.disabled(working || hasUnsavedKey)
                    if working {
                        ProgressView().controlSize(.small).accessibilityLabel("Updating connection")
                        Button("Cancel") { operation?.cancel() }
                    }
                }
                if let success = store.testSuccess {
                    Label(success, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("Image processing has not been verified for this configuration.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if messageRevision == store.revision, !message.isEmpty {
                    Text(message).font(.callout).textSelection(.enabled)
                }
                if let warning = store.configurationWarning {
                    Text(warning).font(.callout).foregroundStyle(.orange)
                }
            }
            Section("Your captures") {
                Text("Each selected screenshot or imported image uses your preferred format, then copies the result. AI formats send it to the selected connection. Pass through copies the image locally. On-device text extraction works offline. History keeps captures and results locally according to your History settings. Set the limit to zero to disable history. Codex removes its temporary files after conversion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(accent)
        .onChange(of: store.activeProvider) { _, _ in newKey = "" }
    }

    private var keyControls: some View {
        Group {
            SecureField(store.activeProvider.requiresKey ? "New API key" : "New API key (optional)", text: $newKey).disabled(working)
            if store.activeProvider == .omlx {
                Text("A server key is optional for localhost (127.0.0.1). Other server addresses require a key.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Use this provider’s API key. API access and billing are separate from chat subscriptions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Keys are saved separately in Keychain. Opening Settings does not read them. Save a new key before refreshing models or testing.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Save key") { keyAction(.save) }
                    .disabled(working || newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Authorize saved key") { keyAction(.authorize) }.disabled(working)
                Button("Remove saved key") { keyAction(.remove) }.disabled(working)
            }
        }
    }

    private var hasUnsavedKey: Bool {
        store.activeProvider != .codex && !newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func field(_ path: WritableKeyPath<ConnectionProfile, String>) -> Binding<String> {
        Binding(get: { store.activeProfile[keyPath: path] }, set: { value in
            var profile = store.activeProfile
            profile[keyPath: path] = value
            store.update(profile)
        })
    }

    private func show(_ text: String) {
        message = text
        messageRevision = store.revision
    }

    private enum KeyAction: Sendable, Equatable { case save, authorize, remove }
    private func keyAction(_ action: KeyAction) {
        let profile = store.activeProfile
        let account = profile.credentialAccount
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        show("Updating Keychain…")
        operation = Task {
            defer { working = false; operation = nil }
            do {
                let result = try await Task.detached {
                    switch action {
                    case .save:
                        try KeyStore.save(key, account: account)
                        return "Key saved securely. Test image processing to verify this connection."
                    case .authorize:
                        return try KeyStore.read(account: account, allowInteraction: true).isEmpty
                            ? "No API key is saved for this connection."
                            : "Saved key is accessible. Test image processing to verify this connection."
                    case .remove:
                        try KeyStore.save("", account: account)
                        return "Saved key removed."
                    }
                }.value
                store.credentialsDidChange(for: profile)
                guard store.activeProfile == profile else { return }
                if action == .save { newKey = "" }
                show(result)
            } catch {
                if store.activeProfile == profile { show(error.localizedDescription) }
            }
        }
    }

    private func refreshModels() {
        let profile: ConnectionProfile
        do { profile = try store.validatedProfile() }
        catch { show(error.localizedDescription); return }
        let revision = store.revision
        working = true
        show("Loading models…")
        operation = Task {
            defer { working = false; operation = nil }
            do {
                let listed = try await AIService.models(profile: profile)
                try Task.checkCancellation()
                guard store.activeProfile == profile, store.revision == revision else { return }
                var seen = Set<String>()
                models = listed.filter { $0.imageInput != false && seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
                modelsRevision = revision
                show(models.isEmpty ? "No image-capable candidates were listed. Enter a model manually and test image processing." : "Model list refreshed. Choose a model, then test image processing.")
            } catch {
                if store.activeProfile == profile, store.revision == revision {
                    show(error is CancellationError ? "Model refresh cancelled." : error.localizedDescription)
                }
            }
        }
    }

    private func testImageProcessing() {
        let profile: ConnectionProfile
        do { profile = try store.validatedProfile() }
        catch { show(error.localizedDescription); return }
        let revision = store.revision
        store.clearTestSuccess()
        working = true
        show("Testing a synthetic image…")
        operation = Task {
            defer { working = false; operation = nil }
            do {
                let result = try await AIService.test(profile: profile)
                try Task.checkCancellation()
                if store.recordTestSuccess(result, for: profile, revision: revision) { show("") }
            } catch {
                if store.activeProfile == profile, store.revision == revision {
                    show(error is CancellationError ? "Image test cancelled." : error.localizedDescription)
                }
            }
        }
    }

    private func signIn() {
        let profile = store.activeProfile
        store.credentialsDidChange(for: profile)
        let revision = store.revision
        working = true
        show("Complete sign-in in your browser.")
        operation = Task {
            defer { working = false; operation = nil }
            do {
                let path = try AIService.codexPath(profile.executable)
                let (status, _) = try await ProcessRunner().run(path, ["login"], timeout: 300)
                try Task.checkCancellation()
                if store.activeProfile == profile, store.revision == revision {
                    show(status == 0 ? "Sign-in completed. Test image processing to verify ChatGPT access." : "Sign-in did not complete. Try again.")
                }
            } catch {
                if store.activeProfile == profile, store.revision == revision {
                    show(error is CancellationError ? "Sign-in cancelled." : error.localizedDescription)
                }
            }
        }
    }
}
