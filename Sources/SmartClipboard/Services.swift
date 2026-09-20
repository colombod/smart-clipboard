import AppKit
import Carbon
import ClipboardCore
import Security
import Vision

// Runs children without a shell; drains output to a private file to avoid pipe deadlocks.
final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let child = process; lock.unlock()
        if let child, child.isRunning { child.terminate() }
    }
    func run(_ executable: String, _ arguments: [String], directory: URL? = nil, timeout: TimeInterval = 180) async throws -> (Int32, String) {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
                    defer { try? FileManager.default.removeItem(at: log) }
                    do {
                        let handle = try FileHandle(forWritingTo: log)
                        defer { try? handle.close() }
                        let child = Process()
                        child.executableURL = URL(fileURLWithPath: executable)
                        child.arguments = arguments
                        child.currentDirectoryURL = directory
                        child.standardInput = FileHandle.nullDevice
                        child.standardOutput = handle
                        child.standardError = handle
                        var env = ProcessInfo.processInfo.environment
                        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                        // Subscription mode must never silently fall back to an inherited API key.
                        env.removeValue(forKey: "OPENAI_API_KEY")
                        env.removeValue(forKey: "CODEX_API_KEY")
                        child.environment = env
                        self.lock.lock()
                        if self.cancelled { self.lock.unlock(); throw CancellationError() }
                        self.process = child
                        do { try child.run() } catch { self.lock.unlock(); throw error }
                        self.lock.unlock()
                        let deadline = Date().addingTimeInterval(timeout)
                        while child.isRunning {
                            self.lock.lock(); let cancelled = self.cancelled; self.lock.unlock()
                            if cancelled || Date() > deadline {
                                child.terminate()
                                Thread.sleep(forTimeInterval: 0.1)
                                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                                child.waitUntilExit()
                                if cancelled { throw CancellationError() }
                                throw ClipError.message("The operation timed out. Please try again.")
                            }
                            Thread.sleep(forTimeInterval: 0.05)
                        }
                        child.waitUntilExit()
                        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                        continuation.resume(returning: (child.terminationStatus, output))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.cancel() })
    }
}

enum KeyStore {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.smartclipboard.app", kSecAttrAccount as String: "openai-api-key"]
    static func read() -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) throws {
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ClipError.message("Could not remove the key from Keychain (\(status)).") }; return
        }
        let value = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = Data(key.utf8); q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClipError.message("Could not save the key in Keychain (\(status)).") }
    }
}

enum CaptureService {
    static func capture(window: Bool) async throws -> Data? {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ClipError.message("Allow Smart Clipboard in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app.")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: destination) }
        let (status, _) = try await ProcessRunner().run("/usr/sbin/screencapture", (["-i", "-x", "-o", "-t", "png"] + (window ? ["-W"] : []) + [destination.path]), timeout: 300)
        try Task.checkCancellation()
        // Escape produces no file and is a normal cancellation.
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        guard status == 0 else { throw ClipError.message("Screen capture failed. Check Screen Recording permission.") }
        return try Data(contentsOf: destination)
    }
    static func recognize(_ png: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(data: png).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.isEmpty else { throw ClipError.message("No readable text found in this capture.") }
            return text
        }.value
    }
}

enum AIService {
    static func api(png: Data, key: String, model: String, format: OutputFormat, instruction: String) async throws -> ConversionResult {
        guard !key.isEmpty else { throw ClipError.message("Add your OpenAI API key in Settings → Connection, or choose ChatGPT via Codex.") }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClipError.message("Enter an image-capable model in Settings.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"; request.timeoutInterval = 180
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try ConversionProtocol.requestBody(png: png, model: model, format: format, instruction: instruction)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClipError.message("No response from OpenAI.") }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = (object?["error"] as? [String: Any])?["message"] as? String
            throw ClipError.message(detail ?? "OpenAI request failed (HTTP \(http.statusCode)).")
        }
        return try ConversionProtocol.decode(ConversionProtocol.responseText(data), requested: format)
    }
    static func codexPath(_ configured: String) throws -> String {
        let candidates = [configured, NSHomeDirectory() + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/Codex.app/Contents/Resources/codex"]
        guard let path = candidates.first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ClipError.message("Install the Codex CLI, or set its executable path in Settings → Connection.")
        }
        return path
    }
    static func codex(png: Data, executable: String, model: String, format: OutputFormat, instruction: String) async throws -> ConversionResult {
        let path = try codexPath(executable)
        let (status, login) = try await ProcessRunner().run(path, ["login", "status"], timeout: 15)
        guard status == 0, login.localizedCaseInsensitiveContains("ChatGPT") else {
            throw ClipError.message("Sign in with ChatGPT in Settings → Connection first. This option requires Codex access through your ChatGPT plan.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("smart-clipboard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("capture.png")
        let output = folder.appendingPathComponent("result.json")
        try png.write(to: input)
        var args = ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never", "-c", "forced_login_method=\"chatgpt\"", "-c", "features.shell_tool=false", "-c", "features.apply_patch_freeform=false", "-c", "features.collab=false", "-c", "web_search=\"disabled\"", "-C", folder.path, "--image", input.path, "--output-last-message", output.path]
        if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { args += ["--model", model] }
        args += [ConversionProtocol.prompt(format: format, instruction: instruction)]
        let (exit, _) = try await ProcessRunner().run(path, args, directory: folder)
        try Task.checkCancellation()
        guard exit == 0, let text = try? String(contentsOf: output, encoding: .utf8) else {
            throw ClipError.message("Codex could not complete the conversion. Check your sign-in, plan limits, model and CLI version. Update the CLI if necessary.")
        }
        return try ConversionProtocol.decode(text, requested: format)
    }
}

struct Shortcut: Codable, Equatable {
    var key: UInt32
    var modifiers: UInt32
    var label: String
    static let region = Shortcut(key: 20, modifiers: UInt32(cmdKey | shiftKey | optionKey), label: "⌥⇧⌘3")
    static let window = Shortcut(key: 21, modifiers: UInt32(cmdKey | shiftKey | optionKey), label: "⌥⇧⌘4")
}

@MainActor final class HotKeyManager {
    var handler: ((UInt32) -> Void)?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { manager.handler?(id.id) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
    func register(_ shortcut: Shortcut, id: UInt32) throws {
        var ref: EventHotKeyRef?
        if let old = refs.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        let status = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: 0x53434C50, id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw ClipError.message("\(shortcut.label) is already used by another app or macOS. Record a different shortcut.") }
        refs[id] = ref
    }
}
