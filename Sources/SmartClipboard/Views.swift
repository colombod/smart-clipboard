import SwiftUI
import AppKit
import Carbon
import ServiceManagement
import ClipboardCore

// Explicit alias keeps the property wrapper unambiguous on SDKs that also expose a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private let accent = Color(red: 0.20, green: 0.46, blue: 0.35)

struct CaptureView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.png == nil ? "A little clip. A lot of possibility." : "Make your clip useful.").font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text(model.png == nil ? "Capture anything. Keep it in the format you need." : "Choose a format, add a direction, and make it yours.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.png != nil {
                        Button { model.clear() } label: { Image(systemName: "trash") }.help("Discard capture").disabled(model.busy)
                    }
                }
                if let data = model.png, let image = NSImage(data: data) {
                    captureContent(image)
                } else { emptyState }
                if let error = model.error {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        Text(error).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(12).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack(spacing: 6) {
                    Image(systemName: model.notice.isEmpty ? "lock.shield" : "checkmark.circle.fill")
                    Text(model.notice.isEmpty ? "Your capture stays on this Mac until you choose Convert with AI." : model.notice)
                    Spacer()
                }.font(.caption).foregroundStyle(model.notice.isEmpty ? Color.secondary : accent)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.tint(accent).background(Color(nsColor: .windowBackgroundColor))
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "crop.viewfinder").font(.system(size: 23, weight: .medium)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Smart").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Clipboard").font(.system(size: 17, weight: .medium, design: .rounded))
                }
            }.padding(.top, 10)
            VStack(spacing: 8) {
                Button { model.capture() } label: {
                    Label("Capture region", systemImage: "viewfinder").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent)
                Button { model.capture(window: true) } label: {
                    Label("Capture window", systemImage: "macwindow").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
                Button { model.importImage() } label: {
                    Label("Import image", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
            }.disabled(model.busy || model.capturing)
            VStack(alignment: .leading, spacing: 9) {
                Text("OUTPUT FORMAT").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                ForEach(OutputFormat.allCases) { format in
                    Button { model.format = format } label: {
                        HStack(spacing: 10) {
                            Image(systemName: format.symbol).frame(width: 18)
                            Text(format.title)
                            Spacer()
                            if model.format == format { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        }.padding(.horizontal, 10).padding(.vertical, 7)
                            .background(model.format == format ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(model.format == format ? accent : Color.primary)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(model.busy)
                }
            }
            Spacer(minLength: 0)
            Divider()
            Button { model.showSettings() } label: { Label("Settings", systemImage: "gearshape").foregroundStyle(.secondary) }.buttonStyle(.plain)
        }.padding(20).frame(width: 190).frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            .overlay(alignment: .trailing) { Divider() }
    }
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(accent.opacity(0.07)).frame(width: 150, height: 125).rotationEffect(.degrees(-8))
                RoundedRectangle(cornerRadius: 20).fill(Color(nsColor: .controlBackgroundColor)).frame(width: 128, height: 104).shadow(color: .black.opacity(0.07), radius: 15, y: 7)
                Image(systemName: "viewfinder").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(accent)
                Image(systemName: "sparkles").font(.system(size: 24)).foregroundStyle(accent).offset(x: 60, y: -48)
            }
            VStack(spacing: 7) {
                Text("From your screen to your next idea.").font(.system(size: 19, weight: .medium, design: .rounded))
                Text("Turn a table into JSON, a slide into notes,\nor a diagram into editable SVG.").multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(4)
            }
            Button("Capture a region") { model.capture() }.buttonStyle(.borderedProminent).controlSize(.large)
            Text(model.regionShortcut.label + "  anywhere on your Mac").font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Label("Select a region", systemImage: "rectangle.dashed")
                Label("Space for a window", systemImage: "macwindow")
                Label("Esc to cancel", systemImage: "escape")
            }.font(.caption).foregroundStyle(.secondary).padding(.top, 24)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(accent.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 5])) }
    }
    private func captureContent(_ image: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 160)
                    .padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 12) {
                    Text("ORIGINAL CAPTURE").font(.system(size: 10, weight: .semibold)).tracking(1)
                    Text("Keep the image, too.").font(.callout).foregroundStyle(.secondary)
                    Button { model.copyImage() } label: { Label("Copy image", systemImage: "doc.on.doc") }
                    Button { model.save(image: true) } label: { Label("Save PNG…", systemImage: "square.and.arrow.down") }
                }.frame(width: 150).padding(.top, 12)
            }
            if model.format != .image {
                HStack {
                    Image(systemName: "text.bubble").foregroundStyle(.secondary)
                    TextField("Optional direction — e.g. translate to English, preserve table columns…", text: $model.instruction).textFieldStyle(.plain).disabled(model.busy)
                }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                HStack {
                    if model.busy {
                        ProgressView().controlSize(.small)
                        Text("Working on your clip…").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { model.cancel() }
                    } else {
                        Button { model.convert() } label: { Label("Convert with AI", systemImage: "sparkles") }.buttonStyle(.borderedProminent).controlSize(.large)
                        Button("Extract text on device") { model.convert(local: true) }.help("Apple Vision OCR. No upload; ignores additional directions.")
                        Spacer()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.output.isEmpty ? "RESULT" : model.resultFormat.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1)
                    Spacer()
                    if !model.output.isEmpty {
                        Button("Save…") { model.save() }
                        Button { model.copyOutput() } label: { Label("Copy", systemImage: "doc.on.doc") }.keyboardShortcut("c", modifiers: [.command, .shift])
                    }
                }.padding(12)
                Divider()
                if model.output.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: model.format.symbol).font(.title2).foregroundStyle(accent.opacity(0.7))
                        Text(model.format == .image ? "Your image is ready to copy or save." : "Your \(model.format == .auto ? "automatically chosen format" : model.format.title) will appear here.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextEditor(text: $model.output).font(.system(size: 13, design: .monospaced)).padding(8).scrollContentBackground(.hidden)
                }
            }.frame(maxHeight: .infinity).frame(minHeight: 130).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)) }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState<String> private var apiKey = ""
    @ViewState<String> private var message = ""
    @ViewState<Bool> private var working = false
    @ViewState<Task<Void, Never>?> private var loginTask = nil
    @ViewState<Bool> private var loginEnabled = SMAppService.mainApp.status == .enabled
    var body: some View {
        TabView {
            Form {
                Section("AI connection") {
                    Picker("Connect with", selection: $model.provider) {
                        Text("OpenAI API key").tag("api")
                        Text("ChatGPT via Codex").tag("codex")
                    }
                    if model.provider == "api" {
                        SecureField("API key", text: $apiKey).onAppear { apiKey = KeyStore.read() }
                        HStack {
                            Button("Save key to Keychain") {
                                do { try KeyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines)); message = apiKey.isEmpty ? "Key removed." : "Key saved securely." }
                                catch { message = error.localizedDescription }
                            }
                            Link("Get an API key ↗", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        }
                        TextField("Vision model", text: $model.apiModel)
                        Text("API usage is billed to your OpenAI Platform account. Choose a model that supports images and structured outputs.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Use your ChatGPT plan’s Codex access through the official Codex CLI. Subscription limits and workspace policies apply.").font(.callout).foregroundStyle(.secondary)
                        TextField("Codex executable", text: $model.codexExecutable, prompt: Text("Auto-detect"))
                        TextField("Model (optional)", text: $model.codexModel, prompt: Text("Codex default"))
                        HStack {
                            Button("Sign in with ChatGPT") { signIn() }.disabled(working)
                            Button("Check connection") { checkConnection() }.disabled(working)
                            if working { ProgressView().controlSize(.small); Button("Cancel") { loginTask?.cancel() } }
                        }
                        Link("Install / update Codex CLI ↗", destination: URL(string: "https://developers.openai.com/codex/cli")!)
                        Text("Sign-in opens your browser. Credentials stay with Codex; this app does not read or copy your ChatGPT tokens. A recent CLI with --ignore-user-config is required.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
                Section("Your captures") {
                    Text("Only the selected capture and your direction are sent when you choose Convert with AI. Image copying and on-device text extraction work offline. Captures and results stay in memory until discarded or the app quits; Codex uses temporary files that are removed after conversion.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Connection", systemImage: "network") }
            Form {
                Section("Capture shortcuts") {
                    ShortcutRow(title: "Capture region", shortcut: model.regionShortcut) { try model.setShortcut($0, window: false) }
                    ShortcutRow(title: "Capture window", shortcut: model.windowShortcut) { try model.setShortcut($0, window: true) }
                    Text("Click a shortcut and press a new combination with ⌘ or ⌃. Press Escape to cancel. During capture, press Space to switch between a rectangle and a window.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Screen access") {
                    Text("macOS asks for Screen Recording permission the first time you capture. You may need to quit and reopen the app after granting access.").font(.callout)
                    Button("Open Screen Recording settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
                }
            }.formStyle(.grouped).tabItem { Label("Shortcuts", systemImage: "keyboard") }
            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { enabled in
                        do { try model.setLaunchAtLogin(enabled); loginEnabled = SMAppService.mainApp.status == .enabled; message = SMAppService.mainApp.status == .requiresApproval ? "Approve Smart Clipboard in System Settings → General → Login Items." : "" }
                        catch { message = error.localizedDescription }
                    }))
                    Text("Move Smart Clipboard to Applications before enabling launch at login.").font(.caption).foregroundStyle(.secondary)
                    Picker("Default output", selection: $model.defaultFormat) { ForEach(OutputFormat.allCases) { Text($0.title).tag($0) } }
                    Toggle("Copy result after conversion", isOn: $model.copyAutomatically)
                }
                Section("Smart Clipboard") {
                    Text("Capture once. Use it anywhere.").font(.headline)
                    Text("Native macOS · Version 0.1.0\nThe app stays in your menu bar when you close its windows.").foregroundStyle(.secondary)
                }
                if !message.isEmpty { Text(message).font(.callout) }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "slider.horizontal.3") }
        }.padding(12).frame(width: 640, height: 550).tint(accent)
    }
    private func signIn() {
        working = true; message = "Complete sign-in in your browser."
        loginTask = Task {
            defer { working = false; loginTask = nil }
            do {
                let path = try AIService.codexPath(model.codexExecutable)
                let (status, _) = try await ProcessRunner().run(path, ["login"], timeout: 300)
                message = status == 0 ? "Signed in. Use Check connection to confirm ChatGPT access." : "Sign-in did not complete. Try again."
            } catch { message = error is CancellationError ? "Sign-in cancelled." : error.localizedDescription }
        }
    }
    private func checkConnection() {
        working = true; message = "Checking Codex…"
        loginTask = Task {
            defer { working = false; loginTask = nil }
            do {
                let path = try AIService.codexPath(model.codexExecutable)
                let (status, text) = try await ProcessRunner().run(path, ["login", "status"], timeout: 15)
                message = status == 0 && text.localizedCaseInsensitiveContains("ChatGPT") ? "Connected with ChatGPT." : "No ChatGPT sign-in found. Choose Sign in with ChatGPT."
            } catch { message = error.localizedDescription }
        }
    }
}

struct ShortcutRow: View {
    let title: String
    let shortcut: Shortcut
    let save: (Shortcut) throws -> Void
    @ViewState<Bool> private var recording = false
    @ViewState<Any?> private var monitor = nil
    @ViewState<String> private var error = ""
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title); Spacer()
                Button(recording ? "Press shortcut…" : shortcut.label) { begin() }.font(.system(.body, design: .monospaced))
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        }.onDisappear { end() }
    }
    private func end() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false }
    private func begin() {
        end(); recording = true; error = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { end(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.control) else { error = "Include Command or Control."; return nil }
            var modifiers: UInt32 = 0; var label = ""
            if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
            if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
            label += event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            do { try save(Shortcut(key: UInt32(event.keyCode), modifiers: modifiers, label: label)); end() }
            catch { self.error = error.localizedDescription; end() }
            return nil
        }
    }
}
