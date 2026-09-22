import AppKit
import Testing
import ClipboardCore
import Yams
@testable import SmartClipboard

/// Explicit opt-in only. This exercises live image processing and the import path;
/// it does not establish native capture, global shortcuts, focus, or actual-paste UAT.
@MainActor struct OMLXLiveTests {
    private static let instruction = "Preserve the visible code, item names, and quantities exactly in every output, including descriptions and SVG text. Include all table contents."

    @Test func fixtureChecksRejectFormattingAndAssociationErrors() {
        let table = "Code: 123456\n| Item | Quantity |\n|---|---|\n| Juniper | 27 |\n| Quartz | 64 |"
        #expect(!failures(in: ConversionResult(format: .text, content: table), requested: .text, code: "123456").isEmpty)
        let nestedEnvelope = "format: yaml\ncontent: |\n  code: 123456\n  Juniper: 27\n  Quartz: 64"
        #expect(!failures(in: ConversionResult(format: .yaml, content: nestedEnvelope), requested: .yaml, code: "123456").isEmpty)
        let swapped = #"{"code":"123456","items":[{"item":"Juniper","quantity":64},{"item":"Quartz","quantity":27}]}"#
        #expect(!failures(in: ConversionResult(format: .json, content: swapped), requested: .json, code: "123456").isEmpty)
        let flattened = #"{"code":"123456","item_1":"Juniper","quantity_1":64,"item_2":"Quartz","quantity_2":27}"#
        #expect(!failures(in: ConversionResult(format: .json, content: flattened), requested: .json, code: "123456").isEmpty)
        let correct = "code: '123456'\nitems:\n  - item: Juniper\n    quantity: 27\n  - item: Quartz\n    quantity: 64"
        #expect(failures(in: ConversionResult(format: .yaml, content: correct), requested: .yaml, code: "123456").isEmpty)
        for format in [OutputFormat.html, .svg] {
            let prose = "Code 123456: Juniper 27, Quartz 64."
            #expect(!failures(in: ConversionResult(format: format, content: prose), requested: format, code: "123456").isEmpty)
        }
        #expect(!failures(in: ConversionResult(format: .description, content: table), requested: .description, code: "123456").isEmpty)
    }

    @Test func fixtureChecksRejectInventedCorrectionsAndChangedCanvas() {
        let caption = "The inventory table has code 123456 and two item rows: Juniper with quantity 27, and Quartz with quantity 64."
        #expect(failures(in: ConversionResult(format: .description, content: caption), requested: .description, code: "123456").isEmpty)
        for invented in ["Quartz appears to be a misspelling of Quartz.", "Quartz contains a typographical error."] {
            let result = ConversionResult(format: .description, content: caption + " " + invented)
            #expect(failures(in: result, requested: .description, code: "123456").contains { $0.contains("invented correction") })
        }

        // Isolate the canvas check here; full table geometry still requires visual review.
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 680"><text x="60" y="60">Code 123456 Juniper 27 Quartz 64</text></svg>"#
        for viewBox in ["0 0 1200 680", "0 0 600 340"] {
            let result = ConversionResult(format: .svg, content: svg.replacingOccurrences(of: "0 0 1200 680", with: viewBox))
            #expect(failures(in: result, requested: .svg, code: "123456").isEmpty)
        }
        let square = ConversionResult(format: .svg, content: svg.replacingOccurrences(of: "0 0 1200 680", with: "0 0 600 600"))
        #expect(failures(in: square, requested: .svg, code: "123456").contains { $0.contains("aspect ratio") })
        let emptyCanvas = ConversionResult(format: .svg, content: svg.replacingOccurrences(of: "0 0 1200 680", with: "0 0 1200 0"))
        #expect(!failures(in: emptyCanvas, requested: .svg, code: "123456").isEmpty)
    }

    @Test(.enabled(if: OMLXLiveEnvironment.enabled))
    func generatedImageFormatsAndImportedImageHistory() async throws {
        let profile = ConnectionProfile(provider: .omlx, model: OMLXLiveEnvironment.value("MODEL"), endpoint: OMLXLiveEnvironment.value("URL"))
        // This fixture supports an explicitly selected, unauthenticated loopback server.
        // Validate the address locally before creating a session or any result artifacts.
        _ = try OMLXAdapter().modelsRequest(profile: profile, key: "")
        let configuredResults = OMLXLiveEnvironment.value("RESULTS")
        let base = configuredResults.isEmpty ? FileManager.default.temporaryDirectory : URL(fileURLWithPath: configuredResults, isDirectory: true)
        let directory = base.appendingPathComponent("omlx-live-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        print("oMLX live-test artifacts: \(directory.path)")

        let code = String(Int.random(in: 100_000...999_999))
        let png = try fixturePNG(code: code)
        try png.write(to: directory.appendingPathComponent("fixture.png"), options: .atomic)
        var report = OMLXLiveReport(server: profile.endpoint, model: profile.model,
                                    serverBuild: OMLXLiveEnvironment.value("SERVER_BUILD"), code: code)
        try save(report, to: directory)
        let client = ProviderClient()
        defer { client.session.invalidateAndCancel() }

        let formats: [OutputFormat] = [.text, .markdown, .json, .yaml, .html, .svg, .description, .auto]
        for format in formats {
            let start = ProcessInfo.processInfo.systemUptime
            var attempt = OMLXLiveAttempt(phase: "provider", requestedFormat: format.rawValue)
            do {
                // Expected values are never included in the request's text; only the PNG contains them.
                let conversion = try await client.convert(png: png, profile: profile, key: "", format: format, instruction: Self.instruction)
                attempt.actualFormat = conversion.result.format.rawValue
                attempt.failures = failures(in: conversion.result, requested: format, code: code)
                attempt.resultFile = "\(format.rawValue).\(conversion.result.format.fileExtension)"
                try conversion.result.content.write(to: directory.appendingPathComponent(attempt.resultFile!), atomically: true, encoding: .utf8)
            } catch {
                attempt.failures.append(error.localizedDescription)
            }
            attempt.seconds = ProcessInfo.processInfo.systemUptime - start
            report.attempts.append(attempt)
            try save(report, to: directory)
            record(attempt)
        }

        let start = ProcessInfo.processInfo.systemUptime
        var imported = OMLXLiveAttempt(phase: "import-history-clipboard", requestedFormat: OutputFormat.text.rawValue)
        do {
            let result = try await verifyImport(png: png, profile: profile, client: client, directory: directory)
            imported.actualFormat = result.format.rawValue
            imported.failures = failures(in: result, requested: .text, code: code)
            imported.resultFile = "imported.txt"
            try result.content.write(to: directory.appendingPathComponent("imported.txt"), atomically: true, encoding: .utf8)
        } catch {
            imported.failures.append(error.localizedDescription)
        }
        imported.seconds = ProcessInfo.processInfo.systemUptime - start
        report.attempts.append(imported)
        report.completed = true
        try save(report, to: directory)
        record(imported)
    }

    private func failures(in result: ConversionResult, requested: OutputFormat, code: String) -> [String] {
        var failures: [String] = []
        if requested == .auto {
            if result.format == .auto || result.format == .image { failures.append("Auto did not resolve to an editable format.") }
        } else if result.format != requested {
            failures.append("The declared output format differs from the requested format.")
        }
        for value in [code, "Juniper", "Quartz", "27", "64"] {
            let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: value) + "(?![A-Za-z0-9])"
            if result.content.range(of: pattern, options: .regularExpression) == nil {
                failures.append("Visible value missing or changed: \(value).")
            }
        }
        if result.format == .description {
            if result.content.range(of: #"(?m)^\s*\|.*\|\s*$"#, options: .regularExpression) != nil ||
                result.content.range(of: #"(?i)\b(table|grid)\b"#, options: .regularExpression) == nil {
                failures.append("Description transcribed the table without describing its visible structure in prose.")
            }
            // This generated English fixture contains correctly spelled labels and no corrections.
            // This is a fixture assertion, not a production filter for arbitrary screenshot prose.
            let inventedCorrection = #"(?i)\b(misspell(?:ed|ing|ings|s)?|typos?|typographical\s+(?:errors?|mistakes?)|spelling\s+(?:errors?|mistakes?|corrections?))\b"#
            if result.content.range(of: inventedCorrection, options: .regularExpression) != nil {
                failures.append("Description added an invented correction or spelling-error claim absent from this fixture.")
            }
        }
        if result.format == .text {
            // This fixture has a drawn grid, not literal Markdown in its visible text.
            if result.content.range(of: #"(?m)^\s*\|.*\|\s*$|^\s*```"#, options: .regularExpression) != nil {
                failures.append("Plain text introduced Markdown table or code-fence syntax.")
            }
            for (item, quantity) in [("Juniper", "27"), ("Quartz", "64")] {
                if result.content.range(of: "\\b\(item)\\b[^\\n]*\\b\(quantity)\\b", options: .regularExpression) == nil {
                    failures.append("Plain text lost the row association for \(item).")
                }
            }
        }
        if result.format == .json || result.format == .yaml {
            do {
                let tree: Any
                if result.format == .json {
                    tree = try JSONSerialization.jsonObject(with: Data(result.content.utf8), options: [.fragmentsAllowed])
                } else {
                    tree = try Yams.load(yaml: result.content) as Any
                }
                if let root = tree as? [String: Any], Set(root.keys) == ["format", "content"] {
                    failures.append("Structured content repeated the transport envelope instead of the visible record.")
                }
                for (item, quantity) in [("Juniper", "27"), ("Quartz", "64")] {
                    if !hasRecord(tree, item: item, quantity: quantity) {
                        failures.append("Structured output lost the record association for \(item) and \(quantity).")
                    }
                }
            } catch {
                failures.append("Structured content could not be parsed: \(error.localizedDescription)")
            }
        }
        if result.format == .html {
            let rowPattern = #"(?is)<tr\b[^>]*>(.*?)</tr\s*>"#
            let expression = try! NSRegularExpression(pattern: rowPattern)
            let rows = expression.matches(in: result.content, range: NSRange(result.content.startIndex..., in: result.content)).compactMap {
                Range($0.range(at: 1), in: result.content).map { String(result.content[$0]) }
            }
            if result.content.range(of: #"(?i)<table\b"#, options: .regularExpression) == nil {
                failures.append("HTML did not reconstruct the visible table as a table element.")
            }
            for (item, quantity) in [("Juniper", "27"), ("Quartz", "64")] {
                if !rows.contains(where: { $0.contains(item) && $0.range(of: "\\b\(quantity)\\b", options: .regularExpression) != nil }) {
                    failures.append("HTML lost the table-row association for \(item).")
                }
            }
        }
        if result.format == .svg {
            let document = OMLXLiveSVG()
            let parser = XMLParser(data: Data(result.content.utf8))
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = document
            if !parser.parse() || !document.hasSVGRoot || !document.hasViewBox || document.hasHTML {
                failures.append("SVG must be well-formed XML with an SVG root, viewBox, and no HTML table elements.")
            }
            if let aspectRatio = document.aspectRatio, abs(aspectRatio / (1200.0 / 680.0) - 1) > 0.01 {
                failures.append("SVG changed the source canvas aspect ratio instead of preserving the 1200 × 680 fixture.")
            }
            for value in [code, "Juniper", "Quartz", "27", "64"] {
                let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: value) + "(?![A-Za-z0-9])"
                if document.visibleText.range(of: pattern, options: .regularExpression) == nil {
                    failures.append("SVG omitted editable text for \(value).")
                }
            }
        }
        return failures
    }

    private func hasRecord(_ node: Any, item: String, quantity: String) -> Bool {
        if let fields = node as? [String: Any] {
            func isQuantity(_ value: Any) -> Bool {
                if let number = value as? NSNumber { return number.stringValue == quantity }
                return value as? String == quantity
            }
            if let value = fields[item], isQuantity(value) { return true }
            let itemCount = fields.values.filter { ["Juniper", "Quartz"].contains($0 as? String ?? "") }.count
            let quantityCount = fields.values.filter {
                let value = ($0 as? NSNumber)?.stringValue ?? ($0 as? String ?? "")
                return ["27", "64"].contains(value)
            }.count
            if itemCount == 1, quantityCount == 1,
               fields.values.contains(where: { $0 as? String == item }), fields.values.contains(where: isQuantity) { return true }
            return fields.values.contains { hasRecord($0, item: item, quantity: quantity) }
        }
        if let rows = node as? [Any] { return rows.contains { hasRecord($0, item: item, quantity: quantity) } }
        return false
    }

    private func verifyImport(png: Data, profile: ConnectionProfile, client: ProviderClient, directory: URL) async throws -> ConversionResult {
        let history = directory.appendingPathComponent("isolated-history", isDirectory: true)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Previous private clipboard", forType: .string)
        var calls = 0
        let capture = CaptureClient(hasAccess: { false }, requestAccess: { false }, takeImage: { _ in
            throw ClipError.message("The import test must never capture the screen.")
        })
        let model = AppModel(defaults: OMLXLiveDefaults(), historyDirectory: history, registerHotkeys: false,
                             captureClient: capture, pasteboard: board, presentsWindows: false,
                             providerConversionOverride: { image, selected, format, instruction in
            calls += 1
            guard selected == profile else { throw ClipError.message("Import changed the selected connection.") }
            return try await client.convert(png: image, profile: selected, key: "", format: format, instruction: instruction)
        })
        defer { model.cancel() }
        model.connections.update(profile)
        model.connections.activeProvider = .omlx
        model.defaultFormat = .text
        model.defaultInstruction = Self.instruction
        model.processImportedImage(png, source: "Synthetic oMLX live-test image")
        let deadline = ProcessInfo.processInfo.systemUptime + 420
        while (model.busy || model.capturing) && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !model.busy && !model.capturing else { throw ClipError.message("Imported-image conversion timed out.") }
        if let error = model.error { throw ClipError.message(error) }
        guard calls == 1, model.png == png, model.resultFormat == .text,
              !model.output.isEmpty, board.string(forType: .string) == model.output else {
            throw ClipError.message("Import did not preserve the image and copy exactly one live conversion to the private clipboard.")
        }
        let store = try HistoryStore(directory: history)
        guard store.entries.count == 1, let entry = store.entries.first, entry.conversions.count == 1,
              let saved = entry.conversions.first, saved.format == .text, saved.content == model.output,
              saved.provenance == ConversionProvenance(providerID: "omlx", profileID: profile.id, requestedModel: profile.model),
              try store.image(for: entry.id) == png else {
            throw ClipError.message("Imported result, original image, or provider provenance did not survive a history reload.")
        }
        let result = ConversionResult(format: saved.format, content: saved.content)
        model.clear()
        board.clearContents()
        board.setString("Changed private clipboard", forType: .string)
        let clipboardRevision = board.changeCount
        model.openHistory(entry, showWindow: false)
        guard calls == 1, model.output == result.content, board.changeCount == clipboardRevision,
              board.string(forType: .string) == "Changed private clipboard" else {
            throw ClipError.message("Reopening history called the provider or changed the private clipboard.")
        }
        return result
    }

    private func fixturePNG(code: String) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 680,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 680).fill()
        func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat) {
            (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.black
            ])
        }
        text("Inventory record", x: 60, y: 590, size: 42)
        text("Code: \(code)", x: 60, y: 505, size: 52)
        let grid = NSBezierPath(rect: NSRect(x: 60, y: 120, width: 1080, height: 310))
        for y in [CGFloat(220), 320] { grid.move(to: NSPoint(x: 60, y: y)); grid.line(to: NSPoint(x: 1140, y: y)) }
        grid.move(to: NSPoint(x: 740, y: 120)); grid.line(to: NSPoint(x: 740, y: 430))
        NSColor.black.setStroke(); grid.lineWidth = 3; grid.stroke()
        text("Item", x: 84, y: 350, size: 44); text("Quantity", x: 766, y: 350, size: 44)
        text("Juniper", x: 84, y: 250, size: 44); text("27", x: 766, y: 250, size: 44)
        text("Quartz", x: 84, y: 150, size: 44); text("64", x: 766, y: 150, size: 44)
        context.flushGraphics()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func save(_ report: OMLXLiveReport, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
    }

    private func record(_ attempt: OMLXLiveAttempt) {
        let state = attempt.failures.isEmpty ? "PASS" : "FAIL"
        print("oMLX \(attempt.phase) \(attempt.requestedFormat): \(state), \(String(format: "%.2f", attempt.seconds)) seconds")
        for failure in attempt.failures { Issue.record("oMLX \(attempt.phase) \(attempt.requestedFormat): \(failure)") }
    }
}

private enum OMLXLiveEnvironment {
    static func value(_ suffix: String) -> String {
        (ProcessInfo.processInfo.environment["SMART_CLIPBOARD_OMLX_TEST_" + suffix] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var enabled: Bool { !value("URL").isEmpty && !value("MODEL").isEmpty }
}

private struct OMLXLiveAttempt: Codable {
    let phase: String
    let requestedFormat: String
    var actualFormat: String?
    var seconds: Double = 0
    var resultFile: String?
    var failures: [String] = []
}

private struct OMLXLiveReport: Encodable {
    let server: String
    let model: String
    let serverBuild: String
    let code: String
    let scope = "Synthetic-image live API and windowless import/history/private-clipboard checks only. Automated syntax/value checks do not establish semantic or visual quality; inspect every output. Native capture, shortcuts, focus, actual paste, and packaged-app LAN permission require separate UAT."
    var completed = false
    var attempts: [OMLXLiveAttempt] = []
}

private final class OMLXLiveSVG: NSObject, XMLParserDelegate {
    var hasSVGRoot = false
    var hasViewBox = false
    var hasHTML = false
    var aspectRatio: Double?
    var visibleText = ""
    private var depth = 0
    private var textDepth: Int?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if depth == 0 {
            hasSVGRoot = elementName == "svg" && namespaceURI == "http://www.w3.org/2000/svg"
            if let components = attributes["viewBox"]?.split(whereSeparator: { $0.isWhitespace || $0 == "," }), components.count == 4 {
                let values = components.compactMap { Double($0) }
                hasViewBox = values.count == 4 && values.allSatisfy(\.isFinite) && values[2] > 0 && values[3] > 0
                if hasViewBox { aspectRatio = values[2] / values[3] }
            }
        }
        depth += 1
        if ["table", "tr", "th", "td", "foreignObject"].contains(elementName) { hasHTML = true }
        if elementName == "text" { textDepth = depth }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if textDepth != nil { visibleText += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if textDepth == depth { textDepth = nil; visibleText += "\n" }
        depth -= 1
    }
}

/// Settings migration and writes stay entirely in memory; no user preference domain is touched.
private final class OMLXLiveDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
    override func integer(forKey defaultName: String) -> Int { values[defaultName] as? Int ?? 0 }
}
