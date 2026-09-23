import SwiftUI
import AppKit
import Carbon
import ServiceManagement
import ClipboardCore

// Explicit alias keeps the property wrapper unambiguous on SDKs that also expose a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>
private typealias RecorderFocus<Value: Hashable> = SwiftUI.FocusState<Value>

let accent = Color(nsColor: NSColor(name: nil) { appearance in
    switch appearance.bestMatch(from: [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua]) {
    case .accessibilityHighContrastDarkAqua: return NSColor(srgbRed: 0.61, green: 0.88, blue: 0.72, alpha: 1)
    case .accessibilityHighContrastAqua: return NSColor(srgbRed: 0.12, green: 0.34, blue: 0.23, alpha: 1)
    case .darkAqua: return NSColor(srgbRed: 0.44, green: 0.75, blue: 0.59, alpha: 1)
    default: return NSColor(srgbRed: 0.20, green: 0.46, blue: 0.35, alpha: 1)
    }
})
// Native prominent buttons keep white labels, so their fill must stay dark
// even when foreground accents become lighter in Dark Mode.
private let prominentAccent = Color(red: 0.20, green: 0.46, blue: 0.35)

struct CaptureView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.png == nil ? L10n.text("A little clip. A lot of possibility.") : L10n.text("Make your clip useful.")).font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text(model.png == nil ? L10n.text("Capture anything. Keep it in the format you need.") : L10n.text("Choose a format, add a direction, and make it yours.")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.png != nil {
                        Button { model.clear() } label: { Image(systemName: "xmark") }.help(L10n.text("Close clip; keep saved history")).disabled(model.busy)
                            .accessibilityLabel(L10n.text("Close current clip"))
                            .accessibilityHint(L10n.text("Keeps the saved capture in history."))
                    }
                }
                if !model.captureReady {
                    HStack {
                        Label(model.screenAccess ? L10n.text("Capture shortcuts need attention") : L10n.text("Screen Recording permission needed"), systemImage: "exclamationmark.triangle.fill")
                        Spacer()
                        if model.screenAccess {
                            Button(L10n.text("Review shortcuts")) { model.showSettings(tab: "shortcuts") }
                        } else {
                            Button(L10n.text("Open System Settings")) { model.openScreenAccessSettings() }
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
                            .accessibilityLabel(L10n.text("Dismiss error"))
                    }.padding(12).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack(spacing: 6) {
                    Image(systemName: model.notice.isEmpty ? "lock.shield" : "checkmark.circle.fill")
                    Text(model.notice.isEmpty ? (model.defaultFormat != .image ? L10n.text("Automatic capture uses your AI connection, then copies the result.") : L10n.text("Pass through copies your screenshot directly without extraction.")) : model.notice)
                    Spacer()
                }.font(.caption).foregroundStyle(model.notice.isEmpty ? Color.secondary : accent)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.tint(accent).background(Color(nsColor: .windowBackgroundColor))
    }
    private var sidebar: some View {
        ScrollView {
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
                    Text(L10n.text("CAPTURE → CLIPBOARD")).font(.system(size: 11, weight: .semibold)).tracking(0.6)
                    Text(model.defaultFormat.title).font(.caption)
                }.foregroundStyle(accent)
            }.buttonStyle(.plain).help(L10n.text("Configure your preferred format and capture workflow"))
                .accessibilityLabel(L10n.text("Capture preferences")).accessibilityValue(model.defaultFormat.title)
            VStack(spacing: 8) {
                Button { model.capture() } label: {
                    Label(L10n.text("Capture region"), systemImage: "viewfinder").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).tint(prominentAccent)
                Button { model.capture(window: true) } label: {
                    Label(L10n.text("Capture window"), systemImage: "macwindow").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
                Button { model.importImage() } label: {
                    Label(L10n.text("Import image"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
            }.disabled(model.busy || model.capturing)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("OUTPUT FORMAT")).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
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
                        .accessibilityLabel(format.title)
                        .accessibilityAddTraits(model.format == format ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
            Divider()
            Button { model.showHistory() } label: {
                HStack { Label(L10n.text("History"), systemImage: "clock.arrow.circlepath"); Spacer(); Text(L10n.text("\(model.history.count)")).foregroundStyle(.secondary) }
            }.buttonStyle(.plain)
            Button { model.showSettings() } label: { Label(L10n.text("Settings"), systemImage: "gearshape").foregroundStyle(.secondary) }.buttonStyle(.plain)
          }.padding(20)
        }.frame(width: 220).frame(maxHeight: .infinity)
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
            }.accessibilityHidden(true)
            VStack(spacing: 7) {
                Text(L10n.text("From your screen to your next idea.")).font(.system(size: 19, weight: .medium, design: .rounded))
                Text(L10n.text("Turn a table into JSON, a slide into notes,\nor a diagram into editable SVG.")).multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(4)
            }
            Button(L10n.text("Capture a region")) { model.capture() }.buttonStyle(.borderedProminent).tint(prominentAccent).controlSize(.large)
            Text(L10n.text("\(model.regionShortcut.label)  anywhere on your Mac")).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Label(L10n.text("Select a region"), systemImage: "rectangle.dashed")
                Label(L10n.text("Space for a window"), systemImage: "macwindow")
                Label(L10n.text("Esc to cancel"), systemImage: "escape")
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
                    .accessibilityLabel(L10n.text("Original capture"))
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("ORIGINAL CAPTURE")).font(.system(size: 10, weight: .semibold)).tracking(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text("Keep the image, too.")).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.copyImage() } label: { Label(L10n.text("Copy image"), systemImage: "doc.on.doc") }
                    Button { model.save(image: true) } label: { Label(L10n.text("Save PNG…"), systemImage: "square.and.arrow.down") }
                }.frame(width: 180).padding(.top, 12)
            }
            if model.format != .image {
                if model.format == .auto {
                    Text(L10n.text("AI picks the most useful format from the source: prose, tables, code, layouts or diagrams.")).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "text.bubble").foregroundStyle(.secondary)
                    TextField(L10n.text("Optional direction — e.g. preserve table columns…"), text: $model.instruction).textFieldStyle(.plain).disabled(model.busy)
                        .accessibilityLabel(L10n.text("Conversion direction"))
                }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                OutputLanguagePicker(title: L10n.text("Output language"), selection: $model.outputLanguage)
                    .disabled(model.busy)
                HStack {
                    if model.busy {
                        ProgressView().controlSize(.small).accessibilityLabel(L10n.text("Converting capture"))
                        Text(L10n.text("Working on your clip…")).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.text("Cancel")) { model.cancel() }
                    } else {
                        Button { model.convert() } label: { Label(L10n.text("Convert with AI"), systemImage: "sparkles") }.buttonStyle(.borderedProminent).tint(prominentAccent).controlSize(.large)
                        Button(L10n.text("Extract text on device")) { model.convert(local: true) }.help(L10n.text("Apple Vision OCR. No upload; keeps the source language and ignores translation and additional directions."))
                        Spacer()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.output.isEmpty ? L10n.text("RESULT") : model.resultFormat.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1)
                        if let origin = model.resultOrigin {
                            Text(origin).font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(origin)
                        }
                    }
                    Spacer()
                    if !model.savedConversions.isEmpty {
                        Menu(L10n.text("Saved formats")) {
                            ForEach(model.savedConversions) { result in
                                Button(result.variantTitle) { model.useSavedConversion(result) }
                            }
                        }.fixedSize().disabled(model.busy)
                    }
                    if !model.output.isEmpty {
                        Button(L10n.text("Save…")) { model.save() }
                        Button { model.copyOutput() } label: { Label(L10n.text("Copy"), systemImage: "doc.on.doc") }.keyboardShortcut("c", modifiers: [.command, .shift])
                    }
                }.padding(12)
                Divider()
                if model.output.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: model.format.symbol).font(.title2).foregroundStyle(accent.opacity(0.7))
                        Text(model.format == .image ? L10n.text("Your image is ready to copy or save.") : (model.format == .auto ? L10n.text("Your automatically chosen format will appear here.") : L10n.text("Your \(model.format.title) will appear here."))).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextEditor(text: $model.output).font(.system(.body, design: .monospaced)).padding(8).scrollContentBackground(.hidden)
                        .accessibilityLabel(L10n.text("Converted result"))
                        .accessibilityHint(L10n.text("Editable \(model.resultFormat.title) content."))
                }
            }.frame(maxHeight: .infinity).frame(minHeight: 130).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)) }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState<String?> private var activeRecorder = nil
    var body: some View {
        TabView(selection: $model.settingsTab) {
            ConnectionSettingsView(store: model.connections)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.text("Connection settings"))
                .tabItem { Label(L10n.text("Connection"), systemImage: "network") }.tag("connection")
            Form {
                Section(L10n.text("App status")) {
                    Label(L10n.text("Running in the background"), systemImage: "checkmark.circle.fill").foregroundStyle(accent)
                    Text(model.menuBarInstalled ? L10n.text("Look for the viewfinder and Clip in the menu bar.") : L10n.text("Menu bar button could not be created. Reopen the app.")).font(.caption)
                    Text(L10n.text("Closing a window keeps the app running. A crowded menu bar or a menu bar manager can hide buttons; opening Smart Clipboard from Applications always brings its window back.")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("Screen access")) {
                    Label(model.screenAccess ? L10n.text("Screen Recording allowed") : L10n.text("Screen Recording permission needed"), systemImage: model.screenAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.screenAccess ? accent : .orange)
                    if !model.screenAccess {
                        Text(L10n.text("Enable Smart Clipboard in Privacy & Security → Screen & System Audio Recording, then quit and reopen this app. If it is already enabled after an update, turn its permission off and on again.")).font(.caption)
                        Button(L10n.text("Request screen access")) { model.requestScreenAccess() }
                        Button(L10n.text("Open Screen Recording settings")) { model.openScreenAccessSettings() }
                    }
                    Button(L10n.text("Check again")) { model.refreshReadiness() }
                }
                Section(L10n.text("Capture shortcuts")) {
                    ShortcutRow(title: L10n.text("Capture region"), shortcut: model.regionShortcut, status: model.shortcutStatus(1), activeRecorder: $activeRecorder, pause: model.pauseShortcuts, resume: model.resumeShortcuts) { try model.setShortcut($0, window: false) }
                    ShortcutRow(title: L10n.text("Capture window"), shortcut: model.windowShortcut, status: model.shortcutStatus(2), activeRecorder: $activeRecorder, pause: model.pauseShortcuts, resume: model.resumeShortcuts) { try model.setShortcut($0, window: true) }
                    Button(L10n.text("Find available shortcuts")) { model.findAvailableShortcuts() }.disabled(activeRecorder != nil)
                    Text(L10n.text("Checks enabled macOS shortcuts and registrations held by other apps. macOS does not expose the owner of every shortcut or shortcuts intercepted by keyboard utilities.")).font(.caption).foregroundStyle(.secondary)
                    Text(L10n.text("Click a shortcut and press a combination with ⌘ or ⌃. Escape cancels. Shortcuts pause while you record. During capture, Space switches between region and window.")).font(.caption).foregroundStyle(.secondary)
                    Text(model.lastShortcutEvent).font(.caption.monospaced()).textSelection(.enabled)
                }
            }.formStyle(.grouped)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.text("Shortcut settings"))
                .tabItem { Label(L10n.text("Shortcuts"), systemImage: "keyboard") }.tag("shortcuts")
            GeneralSettingsView(model: model)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.text("General settings"))
                .tabItem { Label(L10n.text("General"), systemImage: "slider.horizontal.3") }.tag("general")
            HistorySettingsView(model: model)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.text("History settings"))
                .tabItem { Label(L10n.text("History"), systemImage: "clock.arrow.circlepath") }.tag("history")
            AboutView(updates: model.updates)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.text("About Smart Clipboard"))
                .tabItem { Label(L10n.text("About"), systemImage: "info.circle") }.tag("about")
        }.padding(12).frame(minWidth: 640, maxWidth: .infinity, minHeight: 550, maxHeight: .infinity).tint(accent)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState<String> private var message = ""
    @ViewState<Bool> private var loginEnabled = SMAppService.mainApp.status == .enabled
    var body: some View {
Form {
                Section(L10n.text("General")) {
                    Toggle(L10n.text("Launch at login"), isOn: Binding(get: { loginEnabled }, set: { enabled in
                        do { try model.setLaunchAtLogin(enabled); loginEnabled = SMAppService.mainApp.status == .enabled; message = SMAppService.mainApp.status == .requiresApproval ? L10n.text("Approve Smart Clipboard in System Settings → General → Login Items.") : "" }
                        catch { message = error.localizedDescription }
                    }))
                    Text(L10n.text("Move Smart Clipboard to Applications before enabling launch at login.")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("Capture workflow")) {
                    Picker(L10n.text("Preferred format"), selection: $model.defaultFormat) { ForEach(OutputFormat.allCases) { Text($0.title).tag($0) } }
                    TextField(L10n.text("Default direction"), text: $model.defaultInstruction, prompt: Text(L10n.text("Optional — e.g. preserve table columns")))
                    Text(L10n.text("Every capture uses this format and direction, then copies the result. No app windows open; progress appears in the menu bar. Enable notifications below to hear or see when it is ready to paste or needs attention.")).font(.caption).foregroundStyle(.secondary)
                    Text(L10n.text("Auto detect lets AI choose the best format. Pass through copies the original PNG without extraction or AI. Other formats use your configured connection.")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("Languages")) {
                    Text(L10n.text("Menus and settings follow your Mac’s preferred supported language. English is used when a translation is unavailable.")).font(.caption).foregroundStyle(.secondary)
                    OutputLanguagePicker(title: L10n.text("Capture output"), selection: $model.defaultOutputLanguage)
                    Text(L10n.text("Keep source language preserves the language detected in the image. Choose System language or a specific language to translate every AI capture automatically.")).font(.caption).foregroundStyle(.secondary)
                    Text(L10n.text("This language choice takes priority over translation directions. Pass through keeps the original image; on-device text extraction keeps the source language. You can choose a different language when reopening history.")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("Manual conversions")) {
                    Toggle(L10n.text("Copy after manual conversion"), isOn: $model.copyAutomatically)
                }
                if let notifications = model.notifications {
                    NotificationSettingsView(notifications: notifications)
                }
                Section("Smart Clipboard") {
                    Text(L10n.text("Capture once. Use it anywhere.")).font(.headline)
                    Text(L10n.text("The app stays in your menu bar when you close its windows.")).foregroundStyle(.secondary)
                    Button(L10n.text("About Smart Clipboard…")) { model.settingsTab = "about" }
                }
                if !message.isEmpty { Text(message).font(.callout) }
            }.formStyle(.grouped)
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
    @ViewState<NSWindow?> private var recordingWindow = nil
    @ViewState<String> private var error = ""
    @RecorderFocus private var recorderFocused: Bool
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title); Spacer()
                Button(recording ? L10n.text("Press shortcut…") : shortcut.label) { begin() }.font(.system(.body, design: .monospaced)).disabled(activeRecorder != nil && activeRecorder != title)
                    .focused($recorderFocused)
                    .accessibilityLabel(L10n.text("Record \(title.lowercased()) shortcut"))
                    .accessibilityValue(recording ? L10n.text("Recording") : shortcut.spokenDescription)
                    .accessibilityHint(L10n.text("Activate to record a key combination. Escape cancels; Tab moves to the next control. Control-Option commands pass through while VoiceOver is running."))
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        }.onDisappear { end() }
            .onChange(of: recorderFocused) { _, focused in if !focused { end() } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in end() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in end() }
    }
    private func end() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recordingWindow = nil; recording = false; activeRecorder = nil; resume()
    }
    private func begin() {
        end(); pause(); recording = true; activeRecorder = title; error = ""; recorderFocused = true
        recordingWindow = NSApp.keyWindow
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let recordingWindow, event.window === recordingWindow else { end(); return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch ShortcutRecorderInput.action(keyCode: event.keyCode, modifiers: flags, characters: event.charactersIgnoringModifiers, voiceOverEnabled: NSWorkspace.shared.isVoiceOverEnabled) {
            case .cancel: end(); return nil
            case .navigate: end(); return event
            case .assistiveNavigation: return event
            case .record: break
            }
            guard flags.contains(.command) || flags.contains(.control) else { error = L10n.text("Include Command or Control."); return nil }
            var modifiers: UInt32 = 0; var label = ""
            if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
            if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
            label += event.characters(byApplyingModifiers: [])?.uppercased() ?? L10n.text("Key \(event.keyCode)")
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
                    Text(L10n.text("Your recent clips")).font(.title2.weight(.semibold))
                    Text(L10n.text("Reopen a capture. Choose another format or language.")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("Clear history…"), role: .destructive) { confirmClear = true }.disabled(model.history.isEmpty || model.busy || model.capturing)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if model.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                    Text(model.historyLimit == 0 ? L10n.text("History is turned off") : L10n.text("No saved captures yet")).font(.headline)
                    Text(model.historyLimit == 0 ? L10n.text("Increase the history limit in Settings to save future captures.") : L10n.text("Your next capture or imported image will appear here.")).foregroundStyle(.secondary)
                    Button(L10n.text("History settings")) { model.showSettings(tab: "history") }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.history) { entry in
                            HStack(spacing: 14) {
                                HistoryThumbnail(url: model.historyImageURL(entry)).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.title).font(.headline).lineLimit(1)
                                    Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                    Text(entry.conversions.isEmpty ? L10n.text("Original image") : entry.conversions.map { $0.variantTitle }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }.accessibilityElement(children: .combine)
                                Spacer()
                                Button(L10n.text("Open")) { model.openHistory(entry) }
                                    .accessibilityLabel(L10n.text("Open \(entry.title), captured \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))"))
                                Button(role: .destructive) { model.deleteHistory(entry) } label: { Image(systemName: "trash") }.help(L10n.text("Delete this saved capture and all its formats"))
                                    .accessibilityLabel(L10n.text("Delete \(entry.title), captured \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))"))
                                    .accessibilityHint(L10n.text("Deletes the original image and all its saved formats."))
                            }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                .disabled(model.busy || model.capturing)
                        }
                    }
                }
            }
            HStack {
                Text(L10n.text("\(model.history.count) of \(model.historyLimit) clips · \(ByteCountFormatter.string(fromByteCount: model.historyBytes, countStyle: .file)) on this Mac")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Settings")) { model.showSettings(tab: "history") }
            }
        }.padding(24).frame(minWidth: 490, minHeight: 330).tint(accent)
            .confirmationDialog(L10n.text("Delete all saved captures and results?"), isPresented: $confirmClear) {
                Button(L10n.text("Clear history"), role: .destructive) { model.clearHistory() }
            } message: { Text(L10n.text("This removes the app’s saved history and closes the current clip. Exported files and the system clipboard are unchanged.")) }
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
            Section(L10n.text("Capture history")) {
                Stepper(value: $draftLimit, in: 0...HistoryStore.maximumLimit) {
                    HStack {
                        Text(L10n.text("Keep up to"))
                        TextField(L10n.text("Clips"), value: $draftLimit, format: .number)
                            .accessibilityLabel(L10n.text("Maximum saved clips"))
                            .accessibilityHint(L10n.text("Choose zero to disable history."))
                            .frame(width: 65)
                        Text(L10n.text("clips"))
                    }
                }.disabled(model.busy || model.capturing)
                Button(L10n.text("Apply limit")) { model.setHistoryLimit(draftLimit) }.disabled(model.busy || model.capturing || draftLimit == model.historyLimit || !(0...HistoryStore.maximumLimit).contains(draftLimit))
                Text(L10n.text("Default: 50 clips. Choose 0 to turn history off and remove saved clips. Applying a lower limit removes the oldest captures immediately.")).font(.caption).foregroundStyle(.secondary)
                LabeledContent(L10n.text("Saved captures"), value: L10n.text("\(model.history.count)"))
                LabeledContent(L10n.text("Disk space"), value: ByteCountFormatter.string(fromByteCount: model.historyBytes, countStyle: .file))
                HStack {
                    Button(L10n.text("Open history")) { model.showHistory() }
                    Button(L10n.text("Clear history…"), role: .destructive) { confirmClear = true }.disabled(model.history.isEmpty || model.busy || model.capturing)
                }
            }
            Section(L10n.text("Stored on this Mac")) {
                Text(L10n.text("History keeps original images and the latest result for each format and language across app restarts. Reopen a capture, choose an output language, then convert with AI to save another version. Previous languages remain available under Saved formats. The app does not monitor other apps’ clipboard activity.")).font(.callout).foregroundStyle(.secondary)
                Text(L10n.text("Files are saved in your local Application Support folder with access restricted to your macOS user. They are not separately encrypted by this app. Clearing history does not remove exported files or the system clipboard.")).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error { Text(error).foregroundStyle(.orange).font(.caption) }
        }.formStyle(.grouped)
            .onAppear { draftLimit = model.historyLimit }
            .onChange(of: model.historyLimit) { _, limit in draftLimit = limit }
            .confirmationDialog(L10n.text("Delete all saved captures and results?"), isPresented: $confirmClear) {
                Button(L10n.text("Clear history"), role: .destructive) { model.clearHistory() }
            } message: { Text(L10n.text("This removes local history and closes the current clip. This cannot be undone.")) }
    }
}
