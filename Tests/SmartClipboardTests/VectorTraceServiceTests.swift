import AppKit
import Testing
import ClipboardCore
@testable import SmartClipboard

struct VectorTraceServiceTests {
    private func fixturePNG() throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8,
                                             bytesPerRow: 160, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 8, y: 8, width: 24, height: 24))
        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    private func withExecutable(_ script: String, test: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TraceProcessTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("trace-test")
        try ("#!/bin/sh\n" + script).write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try await test(executable)
    }

    @Test func rejectsUnreadableInputBeforeStartingHelper() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await VectorTraceService(executable: URL(fileURLWithPath: "/missing-helper")).trace(png: Data([1, 2, 3]), settings: TraceSettings())
        }
    }

    @Test func missingBundledHelperIsActionable() async throws {
        do {
            _ = try await VectorTraceService(executable: URL(fileURLWithPath: "/missing-helper")).trace(png: fixturePNG(), settings: TraceSettings())
            Issue.record("Missing executable was accepted")
        } catch { #expect(error.localizedDescription.contains("Reinstall Smart Clipboard")) }
    }

    @Test func cancellationWaitsForChildExitAndReturnsPromptly() async throws {
        try await withExecutable("exec /bin/sleep 30\n") { executable in
            let png = try fixturePNG()
            let started = ContinuousClock.now
            let task = Task { try await VectorTraceService(executable: executable).trace(png: png, settings: TraceSettings()) }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()
            do { _ = try await task.value; Issue.record("Cancelled helper returned a result") }
            catch { #expect(error is CancellationError) }
            #expect(started.duration(to: .now) < .seconds(3))
        }
    }

    @Test func timeoutStopsHelperWithoutWaitingForItsWork() async throws {
        try await withExecutable("exec /bin/sleep 30\n") { executable in
            let started = ContinuousClock.now
            do {
                _ = try await VectorTraceService(executable: executable, timeout: 0.1).trace(png: fixturePNG(), settings: TraceSettings())
                Issue.record("Timed-out helper returned a result")
            } catch { #expect(error.localizedDescription.contains("took too long")) }
            #expect(started.duration(to: .now) < .seconds(3))
        }
    }

    @Test func helperFailureDoesNotExposeItsDiagnosticOutput() async throws {
        try await withExecutable("printf 'private-diagnostic-token' >&2\nexit 1\n") { executable in
            do {
                _ = try await VectorTraceService(executable: executable).trace(png: fixturePNG(), settings: TraceSettings())
                Issue.record("Failed helper returned a result")
            } catch {
                #expect(error.localizedDescription.contains("could not finish"))
                #expect(!error.localizedDescription.contains("private-diagnostic-token"))
            }
        }
    }

    @Test func excessiveHelperOutputIsRejectedEvenAfterSuccessfulExit() async throws {
        let body = "printf '%s' '" + String(repeating: "x", count: 70_000) + "'\n"
        try await withExecutable(body) { executable in
            do {
                _ = try await VectorTraceService(executable: executable).trace(png: fixturePNG(), settings: TraceSettings())
                Issue.record("Unbounded helper response accepted")
            } catch { #expect(error.localizedDescription.contains("too complex")) }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SMART_CLIPBOARD_TRACE_HELPER"] != nil))
    func realNativeHelperProducesValidatedVectorsForEveryPresetAndDetail() async throws {
        let helper = try #require(ProcessInfo.processInfo.environment["SMART_CLIPBOARD_TRACE_HELPER"])
        let png = try fixturePNG()
        for preset in TracePreset.allCases {
            for detail in TraceDetail.allCases {
                let result = try await VectorTraceService(executable: URL(fileURLWithPath: helper)).trace(png: png, settings: TraceSettings(preset: preset, detail: detail))
                #expect(result.engineVersion == "0.6.5")
                #expect(result.svg.contains("<path"))
                #expect(!result.svg.contains("<image"))
                try SVGValidator.validate(result.svg)
            }
        }
    }
}
