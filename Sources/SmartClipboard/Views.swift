import SwiftUI
import AppKit
import Carbon
import ServiceManagement
import ClipboardCore

// Explicit alias keeps the property wrapper unambiguous on SDKs that also expose a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

let accent = Color(red: 0.20, green: 0.46, blue: 0.35)

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
                        Button { model.clear() } label: { Image(systemName: "xmark") }.help("Close clip; keep saved history").disabled(model.busy)
                    }
                }
                if !model.captureReady {
                    HStack {
                        Label(model.screenAccess ? "Capture shortcuts need attention" : "Screen Recording permission needed", systemImage: "exclamationmark.triangle.fill")
                        Spacer()
                        if model.screenAccess {
                            Button("Review shortcuts") { model.showSettings(tab: "shortcuts") }
                        } else {
                            Button("Open System Settings") { model.openScreenAccessSettings() }
                        }
                    }.font(.callout).padding(10).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
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
                    Text(model.notice.isEmpty ? (model.defaultFormat != .image ? "Automatic capture uses your AI connection, then copies the result." : "Pass through copies your screenshot directly without extraction.") : model.notice)
                    Spacer()
                }.font(.caption).foregroundStyle(model.notice.isEmpty ? Color.secondary : accent)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.tint(accent).background(Color(nsColor: .windowBackgroundColor))
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder").font(.system(size: 23, weight: .medium)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Smart").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Clipboard").font(.system(size: 17, weight: .medium, design: .rounded))
                }
            }.padding(.top, 10)
            Button { model.showSettings(tab: "general") } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CAPTURE → CLIPBOARD").font(.system(size: 9, weight: .semibold)).tracking(0.6)
                    Text(model.defaultFormat.title).font(.caption)
                }.foregroundStyle(accent)
            }.buttonStyle(.plain).help("Configure your preferred format and capture workflow")
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
            VStack(alignment: .leading, spacing: 3) {
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
            Button { model.showHistory() } label: {
                HStack { Label("History", systemImage: "clock.arrow.circlepath"); Spacer(); Text("\(model.history.count)").foregroundStyle(.secondary) }
            }.buttonStyle(.plain)
            Button { model.showSettings() } label: { Label("Settings", systemImage: "gearshape").foregroundStyle(.secondary) }.buttonStyle(.plain)
        }.padding(20).frame(width: 200).frame(maxHeight: .infinity)
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
                if model.format == .auto {
                    Text("AI picks the most useful format from the source: prose, tables, code, layouts or diagrams.").font(.caption).foregroundStyle(.secondary)
                }
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.output.isEmpty ? "RESULT" : model.resultFormat.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1)
                        if let origin = model.resultOrigin {
                            Text(origin).font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(origin)
                        }
                    }
                    Spacer()
                    if !model.savedConversions.isEmpty {
                        Menu("Saved formats") {
                            ForEach(model.savedConversions) { result in
                                Button(result.format.title) { model.useSavedConversion(result) }
                            }
                        }.fixedSize().disabled(model.busy)
                    }
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
    @ViewState<String> private var message = ""
    @ViewState<String?> private var activeRecorder = nil
    @ViewState<Bool> private var loginEnabled = SMAppService.mainApp.status == .enabled
    var body: some View {
        TabView(selection: $model.settingsTab) {
            ConnectionSettingsView(store: model.connections)
                .tabItem { Label("Connection", systemImage: "network") }.tag("connection")
            Form {
                Section("App status") {
                    Label("Running in the background", systemImage: "checkmark.circle.fill").foregroundStyle(accent)
                    Text(model.menuBarInstalled ? "Look for the viewfinder and Clip in the menu bar." : "Menu bar button could not be created. Reopen the app.").font(.caption)
                    Text("Closing a window keeps the app running. A crowded menu bar or a menu bar manager can hide buttons; opening Smart Clipboard from Applications always brings its window back.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Screen access") {
                    Label(model.screenAccess ? "Screen Recording allowed" : "Screen Recording permission needed", systemImage: model.screenAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.screenAccess ? accent : .orange)
                    if !model.screenAccess {
                        Text("Enable Smart Clipboard in Privacy & Security → Screen & System Audio Recording, then quit and reopen this app. If it is already enabled after an update, turn its permission off and on again.").font(.caption)
                        Button("Request screen access") { model.requestScreenAccess() }
                        Button("Open Screen Recording settings") { model.openScreenAccessSettings() }
                    }
                    Button("Check again") { model.refreshReadiness() }
                }
                Section("Capture shortcuts") {
                    ShortcutRow(title: "Capture region", shortcut: model.regionShortcut, status: model.shortcutStatus(1), activeRecorder: $activeRecorder, pause: model.pauseShortcuts, resume: model.resumeShortcuts) { try model.setShortcut($0, window: false) }
                    ShortcutRow(title: "Capture window", shortcut: model.windowShortcut, status: model.shortcutStatus(2), activeRecorder: $activeRecorder, pause: model.pauseShortcuts, resume: model.resumeShortcuts) { try model.setShortcut($0, window: true) }
                    Button("Find available shortcuts") { model.findAvailableShortcuts() }.disabled(activeRecorder != nil)
                    Text("Checks enabled macOS shortcuts and registrations held by other apps. macOS does not expose the owner of every shortcut or shortcuts intercepted by keyboard utilities.").font(.caption).foregroundStyle(.secondary)
                    Text("Click a shortcut and press a combination with ⌘ or ⌃. Escape cancels. Shortcuts pause while you record. During capture, Space switches between region and window.").font(.caption).foregroundStyle(.secondary)
                    Text(model.lastShortcutEvent).font(.caption.monospaced()).textSelection(.enabled)
                }
            }.formStyle(.grouped).tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag("shortcuts")
            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { enabled in
                        do { try model.setLaunchAtLogin(enabled); loginEnabled = SMAppService.mainApp.status == .enabled; message = SMAppService.mainApp.status == .requiresApproval ? "Approve Smart Clipboard in System Settings → General → Login Items." : "" }
                        catch { message = error.localizedDescription }
                    }))
                    Text("Move Smart Clipboard to Applications before enabling launch at login.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Capture workflow") {
                    Picker("Preferred format", selection: $model.defaultFormat) { ForEach(OutputFormat.allCases) { Text($0.title).tag($0) } }
                    TextField("Default direction", text: $model.defaultInstruction, prompt: Text("Optional — e.g. translate to English"))
                    Text("Every capture uses this format and direction, then copies the result. No app windows open; progress and errors appear in the menu bar.").font(.caption).foregroundStyle(.secondary)
                    Text("Auto detect lets AI choose the best format. Pass through copies the original PNG without extraction or AI. Other formats use your configured connection.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Manual conversions") {
                    Toggle("Copy after manual conversion", isOn: $model.copyAutomatically)
                }
                Section("Smart Clipboard") {
                    Text("Capture once. Use it anywhere.").font(.headline)
                    Text("The app stays in your menu bar when you close its windows.").foregroundStyle(.secondary)
                    Button("About Smart Clipboard…") { model.settingsTab = "about" }
                }
                if !message.isEmpty { Text(message).font(.callout) }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "slider.horizontal.3") }.tag("general")
            HistorySettingsView(model: model).tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag("history")
            AboutView().tabItem { Label("About", systemImage: "info.circle") }.tag("about")
        }.padding(12).frame(width: 640, height: 550).tint(accent)
    }
}

struct ShortcutRow: View {
    let title: String
    let shortcut: Shortcut
    let status: String
    @Binding var activeRecorder: String?
    let pause: () -> Void
    let resume: () -> Void
    let save: (Shortcut) throws -> Void
    @ViewState<Bool> private var recording = false
    @ViewState<Any?> private var monitor = nil
    @ViewState<String> private var error = ""
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title); Spacer()
                Button(recording ? "Press shortcut…" : shortcut.label) { begin() }.font(.system(.body, design: .monospaced)).disabled(activeRecorder != nil && activeRecorder != title)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        }.onDisappear { end() }
    }
    private func end() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = false; activeRecorder = nil; resume()
    }
    private func begin() {
        end(); pause(); recording = true; activeRecorder = title; error = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { end(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.control) else { error = "Include Command or Control."; return nil }
            var modifiers: UInt32 = 0; var label = ""
            if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
            if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
            label += event.characters(byApplyingModifiers: [])?.uppercased() ?? "Key \(event.keyCode)"
            do { try save(Shortcut(key: UInt32(event.keyCode), modifiers: modifiers, label: label)); end() }
            catch { self.error = error.localizedDescription; end() }
            return nil
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @ViewState<Bool> private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your recent clips").font(.title2.weight(.semibold))
                    Text("Reopen a capture. Give it another format.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear history…", role: .destructive) { confirmClear = true }.disabled(model.history.isEmpty || model.busy || model.capturing)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if model.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                    Text(model.historyLimit == 0 ? "History is turned off" : "No saved captures yet").font(.headline)
                    Text(model.historyLimit == 0 ? "Increase the history limit in Settings to save future captures." : "Your next capture or imported image will appear here.").foregroundStyle(.secondary)
                    Button("History settings") { model.showSettings(tab: "history") }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.history) { entry in
                            HStack(spacing: 14) {
                                HistoryThumbnail(url: model.historyImageURL(entry))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.title).font(.headline).lineLimit(1)
                                    Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                    Text(entry.conversions.isEmpty ? "Original image" : entry.conversions.map { $0.format.title }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Button("Open") { model.openHistory(entry) }
                                Button(role: .destructive) { model.deleteHistory(entry) } label: { Image(systemName: "trash") }.help("Delete this saved capture and all its formats")
                            }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                .disabled(model.busy || model.capturing)
                        }
                    }
                }
            }
            HStack {
                Text("\(model.history.count) of \(model.historyLimit) clips · \(ByteCountFormatter.string(fromByteCount: model.historyBytes, countStyle: .file)) on this Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Settings") { model.showSettings(tab: "history") }
            }
        }.padding(24).frame(minWidth: 490, minHeight: 330).tint(accent)
            .confirmationDialog("Delete all saved captures and results?", isPresented: $confirmClear) {
                Button("Clear history", role: .destructive) { model.clearHistory() }
            } message: { Text("This removes the app’s saved history and closes the current clip. Exported files and the system clipboard are unchanged.") }
    }
}

private struct HistoryThumbnail: View {
    let url: URL?
    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.frame(width: 76, height: 54).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct HistorySettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState<Int> private var draftLimit = HistoryStore.defaultLimit
    @ViewState<Bool> private var confirmClear = false
    var body: some View {
        Form {
            Section("Capture history") {
                Stepper(value: $draftLimit, in: 0...HistoryStore.maximumLimit) {
                    HStack {
                        Text("Keep up to")
                        TextField("Clips", value: $draftLimit, format: .number).frame(width: 65)
                        Text("clips")
                    }
                }.disabled(model.busy || model.capturing)
                Button("Apply limit") { model.setHistoryLimit(draftLimit) }.disabled(model.busy || model.capturing || draftLimit == model.historyLimit || !(0...HistoryStore.maximumLimit).contains(draftLimit))
                Text("Default: 50 clips. Choose 0 to turn history off and remove saved clips. Applying a lower limit removes the oldest captures immediately.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Saved captures", value: "\(model.history.count)")
                LabeledContent("Disk space", value: ByteCountFormatter.string(fromByteCount: model.historyBytes, countStyle: .file))
                HStack {
                    Button("Open history") { model.showHistory() }
                    Button("Clear history…", role: .destructive) { confirmClear = true }.disabled(model.history.isEmpty || model.busy || model.capturing)
                }
            }
            Section("Stored on this Mac") {
                Text("History keeps captured and imported images and the latest result for each output format across app restarts. Reopen an entry to copy a saved result or convert the original into another format. The app does not monitor other apps’ clipboard activity.").font(.callout).foregroundStyle(.secondary)
                Text("Files are saved in your local Application Support folder with access restricted to your macOS user. They are not separately encrypted by this app. Clearing history does not remove exported files or the system clipboard.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error { Text(error).foregroundStyle(.orange).font(.caption) }
        }.formStyle(.grouped)
            .onAppear { draftLimit = model.historyLimit }
            .onChange(of: model.historyLimit) { _, limit in draftLimit = limit }
            .confirmationDialog("Delete all saved captures and results?", isPresented: $confirmClear) {
                Button("Clear history", role: .destructive) { model.clearHistory() }
            } message: { Text("This removes local history and closes the current clip. This cannot be undone.") }
    }
}
