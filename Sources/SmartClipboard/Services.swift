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
                                throw ClipError.message(L10n.text("The operation timed out. Please try again."))
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
    // File-based macOS Keychain ignores some SecItem authentication-UI options.
    // Serialize our operations while temporarily suppressing its legacy prompts.
    private static let lock = NSLock()
    static func query(account: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.smartclipboard.app", kSecAttrAccount as String: account] }
    static func read(account: String = "openai-api-key", allowInteraction: Bool = false) throws -> String {
        lock.lock(); defer { lock.unlock() }
        var previousInteraction = DarwinBoolean(true)
        let previousStatus = SecKeychainGetUserInteractionAllowed(&previousInteraction)
        guard previousStatus == errSecSuccess else { throw ClipError.message(L10n.text("Could not check Keychain access. Open Settings → Connection to authorize your saved key.")) }
        let interactionStatus = SecKeychainSetUserInteractionAllowed(allowInteraction)
        guard interactionStatus == errSecSuccess else { throw ClipError.message(L10n.text("Could not configure Keychain access. Open Settings → Connection to authorize your saved key.")) }
        defer { SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
        var q = query(account: account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowInteraction { q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ClipError.message(L10n.text("The saved API key needs Keychain access. Open Settings → Connection and choose Authorize saved key, or save a new key."))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String, account: String = "openai-api-key") throws {
        lock.lock(); defer { lock.unlock() }
        let query = query(account: account)
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ClipError.message(L10n.text("Could not remove the key from Keychain (\(status)).")) }; return
        }
        let value = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = Data(key.utf8); q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClipError.message(L10n.text("Could not save the key in Keychain (\(status)).")) }
    }
}

enum CaptureService {
    static func capture(window: Bool) async throws -> Data? {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: destination) }
        let (status, output) = try await ProcessRunner().run("/usr/sbin/screencapture", (["-i", "-x", "-o", "-t", "png"] + (window ? ["-W"] : []) + [destination.path]), timeout: 300)
        try Task.checkCancellation()
        return try readCaptureResult(status: status, output: output, destination: destination)
    }
    static func readCaptureResult(status: Int32, output: String, destination: URL) throws -> Data? {
        // An unsuccessful command is not cancellation, even when it produced no image.
        guard status == 0 else {
            throw ClipError.message(L10n.text("Screen capture failed (exit \(status)). \(output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800)) Check Screen Recording permission and reopen the app if it was just granted."))
        }
        // Escape normally exits successfully without writing a file.
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        let data = try Data(contentsOf: destination)
        guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            throw ClipError.message(L10n.text("Screen capture returned an unreadable image. Try capturing again."))
        }
        return data
    }
    static func recognize(_ png: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(data: png).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.isEmpty else { throw ClipError.message(L10n.text("No readable text found in this capture.")) }
            return text
        }.value
    }
}

enum AIService {
    static func api(png: Data, key: String, model: String, format: OutputFormat, instruction: String) async throws -> ConversionResult {
        guard !key.isEmpty else { throw ClipError.message(L10n.text("Add your OpenAI API key in Settings → Connection, or choose ChatGPT via Codex.")) }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClipError.message(L10n.text("Enter an image-capable model in Settings.")) }
        let profile = ConnectionProfile(provider: .openai, model: model)
        let client = ProviderClient()
        defer { client.session.invalidateAndCancel() }
        return try await client.convert(png: png, profile: profile, key: key, format: format, instruction: instruction).result
    }
    static func codexPath(_ configured: String) throws -> String {
        let candidates = [configured, NSHomeDirectory() + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/Codex.app/Contents/Resources/codex"]
        guard let path = candidates.first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ClipError.message(L10n.text("Install the Codex CLI, or set its executable path in Settings → Connection."))
        }
        return path
    }
    static func codex(png: Data, executable: String, model: String, format: OutputFormat, instruction: String) async throws -> ConversionResult {
        let path = try codexPath(executable)
        let (status, login) = try await ProcessRunner().run(path, ["login", "status"], timeout: 15)
        guard status == 0, login.localizedCaseInsensitiveContains("ChatGPT") else {
            throw ClipError.message(L10n.text("Sign in with ChatGPT in Settings → Connection first. This option requires Codex access through your ChatGPT plan."))
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
            throw ClipError.message(L10n.text("Codex could not complete the conversion. Check your sign-in, plan limits, model and CLI version. Update the CLI if necessary."))
        }
        return try ConversionProtocol.decode(text, requested: format)
    }
}

struct Shortcut: Codable, Equatable {
    var key: UInt32
    var modifiers: UInt32
    var label: String
    static var region: Shortcut { captureDefault(window: false) }
    static var window: Shortcut { captureDefault(window: true) }

    static func captureDefault(window: Bool, modifiers: UInt32 = UInt32(cmdKey | controlKey),
                               resolve: (String, UInt32) -> UInt32? = ShortcutKeyResolver.currentKey) -> Shortcut {
        let letter = window ? "W" : "R"
        let resolved = resolve(letter, modifiers)
        let key = resolved ?? UInt32(window ? kVK_ANSI_W : kVK_ANSI_R)
        var label = ""
        for (flag, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(flag) != 0 { label += symbol }
        }
        // If macOS supplies no usable layout, show the physical fallback honestly
        // rather than label an unknown key as R/W. The recorder remains available.
        label += resolved == nil ? L10n.text("Key \(key)") : letter
        return Shortcut(key: key, modifiers: modifiers, label: label)
    }
}
