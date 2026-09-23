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
            Section(L10n.text("AI connection")) {
                Picker(L10n.text("Provider"), selection: $store.activeProvider) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                }
                Text(L10n.text("Captures use this connection. Auto detect chooses the output format; it keeps your selected provider."))
                    .font(.caption).foregroundStyle(.secondary)
                if store.activeProvider == .omlx {
                    TextField(L10n.text("Server address"), text: field(\.endpoint), prompt: Text("http://127.0.0.1:8000/v1"))
                    Text(L10n.text("Connect to an already running oMLX server with an image-capable model. Screenshots go to this address, which may be on this Mac or your local network."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.activeProvider == .codex {
                    TextField(L10n.text("Codex executable"), text: field(\.executable), prompt: Text(L10n.text("Auto-detect")))
                    Text(L10n.text("Use your ChatGPT plan’s Codex access through the official Codex CLI. Credentials stay with Codex. Subscription limits and workspace policies apply."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L10n.text("Sign in with ChatGPT")) { signIn() }.disabled(working)
                    Link(L10n.text("Install / update Codex CLI ↗"), destination: URL(string: "https://developers.openai.com/codex/cli")!)
                } else {
                    keyControls
                }
            }
            Section(L10n.text("Image processing")) {
                TextField(store.activeProvider == .codex ? L10n.text("Model (optional)") : L10n.text("Vision model"), text: field(\.model), prompt: Text(store.activeProvider == .codex ? L10n.text("Codex default") : L10n.text("Enter an image-capable model")))
                if store.activeProvider != .codex {
                    HStack {
                        Button(L10n.text("Refresh models")) { refreshModels() }.disabled(working || hasUnsavedKey)
                        if modelsRevision == store.revision, !models.isEmpty {
                            Menu(L10n.text("Choose a listed model")) {
                                ForEach(models) { model in
                                    Button(model.imageInput == nil ? L10n.text("\(model.id) (image support unverified)") : model.id) {
                                        var profile = store.activeProfile
                                        profile.model = model.id
                                        store.update(profile)
                                    }
                                }
                            }
                        }
                    }
                    Text(L10n.text("Models known to accept only text are hidden. You can enter a model manually; a model list alone does not confirm image support."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(L10n.text("Test image processing sends a small synthetic image with sample text through this connection. It does not use your captures. Provider charges or subscription usage may apply."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("Test image processing")) { testImageProcessing() }.disabled(working || hasUnsavedKey)
                    if working {
                        ProgressView().controlSize(.small).accessibilityLabel(L10n.text("Updating connection"))
                        Button(L10n.text("Cancel")) { operation?.cancel() }
                    }
                }
                if let success = store.testSuccess {
                    Label(success, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text(L10n.text("Image processing has not been verified for this configuration."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if messageRevision == store.revision, !message.isEmpty {
                    Text(message).font(.callout).textSelection(.enabled)
                }
                if let warning = store.configurationWarning {
                    Text(warning).font(.callout).foregroundStyle(.orange)
                }
            }
            Section(L10n.text("Your captures")) {
                Text(L10n.text("Each selected screenshot or imported image uses your preferred format, then copies the result. AI formats send it to the selected connection. Pass through copies the image locally. On-device text extraction works offline. History keeps captures and results locally according to your History settings. Set the limit to zero to disable history. Codex removes its temporary files after conversion."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(accent)
        .onChange(of: store.activeProvider) { _, _ in newKey = "" }
    }

    private var keyControls: some View {
        Group {
            SecureField(store.activeProvider.requiresKey ? L10n.text("New API key") : L10n.text("New API key (optional)"), text: $newKey).disabled(working)
            if store.activeProvider == .omlx {
                Text(L10n.text("A server key is optional for localhost (127.0.0.1). Other server addresses require a key."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L10n.text("Use this provider’s API key. API access and billing are separate from chat subscriptions."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("Keys are saved separately in Keychain. Opening Settings does not read them. Save a new key before refreshing models or testing."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("Save key")) { keyAction(.save) }
                    .disabled(working || newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L10n.text("Authorize saved key")) { keyAction(.authorize) }.disabled(working)
                Button(L10n.text("Remove saved key")) { keyAction(.remove) }.disabled(working)
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
        #if ACCESSIBILITY_AUDIT
        show(L10n.text("Keychain changes are unavailable in the isolated accessibility audit."))
        #else
        let profile = store.activeProfile
        let account = profile.credentialAccount
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        show(L10n.text("Updating Keychain…"))
        operation = Task {
            defer { working = false; operation = nil }
            do {
                let result = try await Task.detached {
                    switch action {
                    case .save:
                        try KeyStore.save(key, account: account)
                        return L10n.text("Key saved securely. Test image processing to verify this connection.")
                    case .authorize:
                        return try KeyStore.read(account: account, allowInteraction: true).isEmpty
                            ? L10n.text("No API key is saved for this connection.")
                            : L10n.text("Saved key is accessible. Test image processing to verify this connection.")
                    case .remove:
                        try KeyStore.save("", account: account)
                        return L10n.text("Saved key removed.")
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
        #endif
    }

    private func refreshModels() {
        #if ACCESSIBILITY_AUDIT
        show(L10n.text("Network requests are unavailable in the isolated accessibility audit."))
        #else
        let profile: ConnectionProfile
        do { profile = try store.validatedProfile() }
        catch { show(error.localizedDescription); return }
        let revision = store.revision
        working = true
        show(L10n.text("Loading models…"))
        operation = Task {
            defer { working = false; operation = nil }
            do {
                let listed = try await AIService.models(profile: profile)
                try Task.checkCancellation()
                guard store.activeProfile == profile, store.revision == revision else { return }
                var seen = Set<String>()
                models = listed.filter { $0.imageInput != false && seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
                modelsRevision = revision
                show(models.isEmpty ? L10n.text("No image-capable candidates were listed. Enter a model manually and test image processing.") : L10n.text("Model list refreshed. Choose a model, then test image processing."))
            } catch {
                if store.activeProfile == profile, store.revision == revision {
                    show(error is CancellationError ? L10n.text("Model refresh cancelled.") : error.localizedDescription)
                }
            }
        }
        #endif
    }

    private func testImageProcessing() {
        #if ACCESSIBILITY_AUDIT
        show(L10n.text("Provider tests are unavailable in the isolated accessibility audit."))
        #else
        let profile: ConnectionProfile
        do { profile = try store.validatedProfile() }
        catch { show(error.localizedDescription); return }
        let revision = store.revision
        store.clearTestSuccess()
        working = true
        show(L10n.text("Testing a synthetic image…"))
        operation = Task {
            defer { working = false; operation = nil }
            do {
                let result = try await AIService.test(profile: profile)
                try Task.checkCancellation()
                if store.recordTestSuccess(result, for: profile, revision: revision) { show("") }
            } catch {
                if store.activeProfile == profile, store.revision == revision {
                    show(error is CancellationError ? L10n.text("Image test cancelled.") : error.localizedDescription)
                }
            }
        }
        #endif
    }

    private func signIn() {
        #if ACCESSIBILITY_AUDIT
        show(L10n.text("Account sign-in is unavailable in the isolated accessibility audit."))
        #else
        let profile = store.activeProfile
        store.credentialsDidChange(for: profile)
        let revision = store.revision
        working = true
        show(L10n.text("Complete sign-in in your browser."))
        operation = Task {
            defer { working = false; operation = nil }
            do {
                let path = try AIService.codexPath(profile.executable)
                let (status, _) = try await ProcessRunner().run(path, ["login"], timeout: 300)
                try Task.checkCancellation()
                if store.activeProfile == profile, store.revision == revision {
                    show(status == 0 ? L10n.text("Sign-in completed. Test image processing to verify ChatGPT access.") : L10n.text("Sign-in did not complete. Try again."))
                }
            } catch {
                if store.activeProfile == profile, store.revision == revision {
                    show(error is CancellationError ? L10n.text("Sign-in cancelled.") : error.localizedDescription)
                }
            }
        }
        #endif
    }
}
