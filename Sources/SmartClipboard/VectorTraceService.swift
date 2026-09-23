import Foundation
import ImageIO
import ClipboardCore

struct VectorTraceResult: Equatable, Sendable {
    let svg: String
    let engineVersion: String
}

/// The production executable is always inside our signed bundle. No model,
/// shell, PATH lookup, user executable preference or inherited credentials.
struct VectorTraceService {
    static let maximumInputBytes = 64 * 1024 * 1024
    static let maximumPixels = 16_000_000
    static let maximumSide = 8_000
    static let maximumOutputBytes = 16 * 1024 * 1024
    let executable: URL
    let timeout: TimeInterval

    init(executable: URL? = nil, timeout: TimeInterval = 90) {
        self.executable = executable ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/SmartClipboardTrace")
        self.timeout = timeout
    }

    func trace(png: Data, settings: TraceSettings) async throws -> VectorTraceResult {
        try Task.checkCancellation()
        try Self.validateInput(png)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ClipError.message(L10n.text("The local tracing component is missing. Reinstall Smart Clipboard to restore it."))
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("smart-clipboard-trace-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("capture.png")
        let output = folder.appendingPathComponent("result.svg")
        try png.write(to: input, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
        let metadata = try await TraceProcess().run(executable: executable, arguments: [
            "--input", input.path, "--output", output.path,
            "--preset", settings.preset.rawValue, "--detail", settings.detail.rawValue
        ], directory: folder, output: output, timeout: timeout)
        try Task.checkCancellation()
        struct Reply: Decodable { let engine: String; let version: String; let paths: Int; let bytes: Int }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: metadata),
              reply.engine == "vtracer", !reply.version.isEmpty, reply.version.utf8.count < 64,
              (1...100_000).contains(reply.paths), (1...Self.maximumOutputBytes).contains(reply.bytes) else {
            throw ClipError.message(L10n.text("The local tracing component returned an invalid result."))
        }
        let attributes = try output.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              attributes.fileSize == reply.bytes else {
            throw ClipError.message(L10n.text("The local tracing component returned an invalid result."))
        }
        let data = try Data(contentsOf: output)
        guard let svg = String(data: data, encoding: .utf8) else {
            throw ClipError.message(L10n.text("The local tracing component returned an invalid result."))
        }
        try SVGValidator.validate(svg)
        try Task.checkCancellation()
        return VectorTraceResult(svg: svg, engineVersion: reply.version)
    }

    private static func validateInput(_ png: Data) throws {
        guard !png.isEmpty, png.count <= maximumInputBytes,
              png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(png as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= maximumSide, height <= maximumSide,
              width <= maximumPixels / height else {
            throw ClipError.message(L10n.text("This image is too large or unreadable for local tracing. Capture a smaller area and try again."))
        }
    }
}

/// One isolated child per operation. All output is bounded while the child is
/// running, and cancellation waits for termination before deleting its files.
private final class TraceProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var child: Process?
    private var cancelled = false

    private func cancel() {
        lock.lock(); cancelled = true; let process = child; lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    func run(executable: URL, arguments: [String], directory: URL, output: URL, timeout: TimeInterval) async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let stdout = directory.appendingPathComponent("reply.json")
                        let stderr = directory.appendingPathComponent("error.txt")
                        for url in [stdout, stderr] {
                            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                                throw ClipError.message(L10n.text("Could not prepare local tracing. Please try again."))
                            }
                        }
                        let out = try FileHandle(forWritingTo: stdout)
                        defer { try? out.close() }
                        let err = try FileHandle(forWritingTo: stderr)
                        defer { try? err.close() }
                        let process = Process()
                        process.executableURL = executable
                        process.arguments = arguments
                        process.currentDirectoryURL = directory
                        process.environment = ["LANG": "C", "LC_ALL": "C", "TMPDIR": directory.path]
                        process.standardInput = FileHandle.nullDevice
                        process.standardOutput = out
                        process.standardError = err
                        self.lock.lock()
                        if self.cancelled { self.lock.unlock(); throw CancellationError() }
                        self.child = process
                        do { try process.run() } catch { self.lock.unlock(); throw error }
                        self.lock.unlock()
                        defer { self.lock.lock(); self.child = nil; self.lock.unlock() }
                        let deadline = ProcessInfo.processInfo.systemUptime + timeout
                        var failure: Error?
                        while process.isRunning {
                            self.lock.lock(); let cancelled = self.cancelled; self.lock.unlock()
                            if cancelled { failure = CancellationError() }
                            else if ProcessInfo.processInfo.systemUptime >= deadline {
                                failure = ClipError.message(L10n.text("Local tracing took too long. Try Balanced detail or capture a smaller area."))
                            } else if Self.fileSize(stdout) > 65_536 || Self.fileSize(stderr) > 65_536 || Self.fileSize(output) > VectorTraceService.maximumOutputBytes {
                                failure = ClipError.message(L10n.text("This trace is too complex. Try Balanced detail or capture a smaller area."))
                            }
                            if failure != nil {
                                process.terminate()
                                Thread.sleep(forTimeInterval: 0.05)
                                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                                break
                            }
                            Thread.sleep(forTimeInterval: 0.02)
                        }
                        process.waitUntilExit()
                        self.lock.lock(); let cancelled = self.cancelled; self.lock.unlock()
                        if cancelled { throw CancellationError() }
                        if let failure { throw failure }
                        guard Self.fileSize(stdout) <= 65_536, Self.fileSize(stderr) <= 65_536,
                              Self.fileSize(output) <= VectorTraceService.maximumOutputBytes else {
                            throw ClipError.message(L10n.text("This trace is too complex. Try Balanced detail or capture a smaller area."))
                        }
                        guard process.terminationStatus == 0 else {
                            throw ClipError.message(L10n.text("Local tracing could not finish. Try another preset or capture a smaller area."))
                        }
                        continuation.resume(returning: try Data(contentsOf: stdout))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.cancel() })
    }

    private static func fileSize(_ url: URL) -> Int {
        // URL resource values can cache an earlier length while a child writes.
        // Read fresh filesystem metadata for every running-process limit check.
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
    }
}
