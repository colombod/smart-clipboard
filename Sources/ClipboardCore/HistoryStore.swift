import Foundation
import CryptoKit

public struct ConversionProvenance: Codable, Equatable, Sendable {
    public var providerID: String
    public var profileID: String?
    public var requestedModel: String
    public var effectiveModel: String?
    public var userEdited: Bool
    public init(providerID: String, profileID: String? = nil, requestedModel: String = "", effectiveModel: String? = nil, userEdited: Bool = false) {
        self.providerID = providerID; self.profileID = profileID; self.requestedModel = requestedModel
        self.effectiveModel = effectiveModel; self.userEdited = userEdited
    }
}

public struct SavedConversion: Codable, Equatable, Identifiable {
    public var id: String { Self.variantID(format: format, outputLanguage: outputLanguage, method: method, traceSettings: traceSettings) }
    public let format: OutputFormat
    /// Large saved results are loaded through HistoryStore.content(for:in:).
    public var content: String {
        didSet { contentArtifact = nil; artifactSHA256 = nil; storedByteCount = nil; storedPreview = nil }
    }
    public var instruction: String
    public var createdAt: Date
    public var provenance: ConversionProvenance?
    /// Resolved BCP 47 target; nil preserves source, "und" preserves legacy directions.
    public var outputLanguage: String?
    public var method: ConversionMethod
    public var traceSettings: TraceSettings?
    public private(set) var contentArtifact: String?
    private var artifactSHA256: String?
    private var storedByteCount: Int?
    private var storedPreview: String?
    public var contentIsExternal: Bool { contentArtifact != nil }
    public var contentByteCount: Int { storedByteCount ?? content.utf8.count }
    public var preview: String { storedPreview ?? String(content.prefix(240)) }
    public init(format: OutputFormat, content: String, instruction: String, createdAt: Date = Date(), provenance: ConversionProvenance? = nil, outputLanguage: String? = nil, method: ConversionMethod? = nil, traceSettings: TraceSettings? = nil) {
        self.format = format; self.content = content; self.instruction = instruction; self.createdAt = createdAt
        self.provenance = provenance
        self.outputLanguage = outputLanguage.flatMap(OutputLanguage.canonicalIdentifier)
        self.method = method ?? Self.legacyMethod(provenance)
        self.traceSettings = self.method == .vtracer ? (traceSettings ?? TraceSettings()) : nil
    }

    private static func legacyMethod(_ provenance: ConversionProvenance?) -> ConversionMethod {
        if provenance?.providerID == "apple-vision" { return .appleVision }
        if provenance?.providerID == "vtracer" { return .vtracer }
        return .ai
    }
    public static func variantID(format: OutputFormat, outputLanguage: String? = nil, method: ConversionMethod = .ai, traceSettings: TraceSettings? = nil) -> String {
        let base = format.rawValue + ":" + (outputLanguage.flatMap(OutputLanguage.canonicalIdentifier)?.lowercased() ?? "source")
        switch method {
        case .ai: return base // Preserve the identifiers of existing AI variants.
        case .appleVision: return base + ":apple-vision"
        case .vtracer: return base + ":vtracer:" + (traceSettings ?? TraceSettings()).variantID
        }
    }
    public func matches(format: OutputFormat, outputLanguage: String? = nil, method: ConversionMethod = .ai, traceSettings: TraceSettings? = nil) -> Bool {
        id == Self.variantID(format: format, outputLanguage: outputLanguage, method: method, traceSettings: traceSettings)
    }

    fileprivate static func validArtifactName(_ name: String) -> Bool {
        guard name.hasPrefix("result-"), name.hasSuffix(".txt") else { return false }
        let uuid = String(name.dropFirst(7).dropLast(4))
        return UUID(uuidString: uuid)?.uuidString == uuid
    }
    fileprivate mutating func externalize(to name: String, data: Data) {
        let sample = String(content.prefix(240))
        content = ""
        contentArtifact = name
        artifactSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        storedByteCount = data.count
        storedPreview = sample
    }
    fileprivate func matchesArtifact(_ data: Data) -> Bool {
        data.count == storedByteCount && SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == artifactSHA256
    }

    private enum CodingKeys: String, CodingKey {
        case format, content, instruction, createdAt, provenance, outputLanguage, method, traceSettings
        case contentArtifact, artifactSHA256, storedByteCount, storedPreview
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(OutputFormat.self, forKey: .format)
        content = container.contains(.content) ? try container.decode(String.self, forKey: .content) : ""
        instruction = try container.decode(String.self, forKey: .instruction)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        provenance = try container.decodeIfPresent(ConversionProvenance.self, forKey: .provenance)
        method = try container.decodeIfPresent(ConversionMethod.self, forKey: .method) ?? Self.legacyMethod(provenance)
        traceSettings = try container.decodeIfPresent(TraceSettings.self, forKey: .traceSettings)
        if method == .vtracer { traceSettings = traceSettings ?? TraceSettings() }
        else { traceSettings = nil }
        contentArtifact = try container.decodeIfPresent(String.self, forKey: .contentArtifact)
        artifactSHA256 = try container.decodeIfPresent(String.self, forKey: .artifactSHA256)
        storedByteCount = try container.decodeIfPresent(Int.self, forKey: .storedByteCount)
        storedPreview = try container.decodeIfPresent(String.self, forKey: .storedPreview)
        if let name = contentArtifact {
            guard content.isEmpty, Self.validArtifactName(name),
                  let count = storedByteCount, (1...HistoryStore.maximumContentBytes).contains(count),
                  let hash = artifactSHA256, hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }),
                  let sample = storedPreview, sample.count <= 240 else {
                throw DecodingError.dataCorruptedError(forKey: .contentArtifact, in: container, debugDescription: "Invalid saved content reference")
            }
        } else {
            guard container.contains(.content), artifactSHA256 == nil, storedByteCount == nil, storedPreview == nil else {
                throw DecodingError.dataCorruptedError(forKey: .content, in: container, debugDescription: "Missing saved content")
            }
        }
        guard method != .vtracer || format == .svg else {
            throw DecodingError.dataCorruptedError(forKey: .method, in: container, debugDescription: "Tracing requires SVG")
        }
        if container.contains(.outputLanguage) {
            if let identifier = try container.decodeIfPresent(String.self, forKey: .outputLanguage) {
                guard let canonical = OutputLanguage.canonicalIdentifier(identifier) else {
                    throw DecodingError.dataCorruptedError(forKey: .outputLanguage, in: container, debugDescription: "Invalid saved output language")
                }
                outputLanguage = canonical
            } else {
                outputLanguage = nil
            }
        } else {
            // Before language selection existed, directions could request a
            // translation. Reopening that result must retain its old behavior.
            outputLanguage = instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "und"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        if contentArtifact == nil { try container.encode(content, forKey: .content) }
        try container.encode(instruction, forKey: .instruction)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(provenance, forKey: .provenance)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(traceSettings, forKey: .traceSettings)
        try container.encodeIfPresent(contentArtifact, forKey: .contentArtifact)
        try container.encodeIfPresent(artifactSHA256, forKey: .artifactSHA256)
        try container.encodeIfPresent(storedByteCount, forKey: .storedByteCount)
        try container.encodeIfPresent(storedPreview, forKey: .storedPreview)
        if let outputLanguage {
            try container.encode(outputLanguage, forKey: .outputLanguage)
        } else {
            // Explicit null distinguishes a new Keep source choice from legacy
            // history that has never recorded an output-language policy.
            try container.encodeNil(forKey: .outputLanguage)
        }
    }
}

public struct HistoryEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let source: String
    public var conversions: [SavedConversion]
    public var title: String {
        // A trace's XML is not a useful capture title; never load its artifact here.
        guard conversions.last?.format != .svg else { return source }
        let firstLine = conversions.last?.preview.split(whereSeparator: \.isNewline).first.map(String.init) ?? source
        return String(firstLine.prefix(80))
    }
}

/// Owned by the main actor in the app. Each original PNG is written once;
/// a small atomic index stores metadata and the latest result per format and output language.
public final class HistoryStore {
    public static let defaultLimit = 50
    public static let maximumLimit = 500
    public static let externalContentThreshold = 64 * 1024
    public static let maximumContentBytes = 16 * 1024 * 1024
    public private(set) var entries: [HistoryEntry] = []
    public private(set) var limit: Int
    public let directory: URL
    private let files = FileManager.default
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    public init(directory: URL, limit: Int = HistoryStore.defaultLimit) throws {
        self.directory = directory
        self.limit = min(max(0, limit), Self.maximumLimit)
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if files.fileExists(atPath: indexURL.path) {
            // Never silently replace an unreadable index with empty history.
            entries = try JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: indexURL))
        }
        let available = entries.filter { files.fileExists(atPath: imageURL(for: $0.id).path) }
        try commit(Array(available.prefix(self.limit)))
    }
    public func imageURL(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".png") }
    public func image(for id: UUID) throws -> Data {
        guard entries.contains(where: { $0.id == id }) else { throw ClipError.message(L10n.text("This capture is no longer in history.")) }
        return try Data(contentsOf: imageURL(for: id))
    }
    public func content(for conversion: SavedConversion, in id: UUID) throws -> String {
        guard let saved = entries.first(where: { $0.id == id })?.conversions.first(where: { $0.id == conversion.id }) else {
            throw ClipError.message(L10n.text("This saved result is no longer in history."))
        }
        guard let name = saved.contentArtifact else { return saved.content }
        do {
            guard SavedConversion.validArtifactName(name) else { throw CocoaError(.fileReadInvalidFileName) }
            let url = directory.appendingPathComponent(name)
            let attributes = try files.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue == saved.contentByteCount else { throw CocoaError(.fileReadCorruptFile) }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumContentBytes + 1) ?? Data()
            guard saved.matchesArtifact(data), let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
            return text
        } catch {
            throw ClipError.message(L10n.text("This saved result could not be read. The original capture is still available."))
        }
    }
    @discardableResult public func add(png: Data, source: String) throws -> HistoryEntry? {
        guard limit > 0 else { return nil }
        let entry = HistoryEntry(id: UUID(), createdAt: Date(), source: source, conversions: [])
        let image = imageURL(for: entry.id)
        try png.write(to: image, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: image.path)
        do { try commit(Array(([entry] + entries).prefix(limit))) }
        catch {
            // Retain the image if the index was committed but later cleanup failed.
            if !entries.contains(where: { $0.id == entry.id }) { try? files.removeItem(at: image) }
            throw error
        }
        return entry
    }
    public func save(_ conversion: SavedConversion, for id: UUID) throws {
        guard let position = entries.firstIndex(where: { $0.id == id }) else { return }
        guard conversion.method != .vtracer || conversion.format == .svg else {
            throw ClipError.message(L10n.text("Tracing results must use SVG."))
        }
        guard conversion.contentByteCount <= Self.maximumContentBytes else {
            throw ClipError.message(L10n.text("This result is too large to save. Try a smaller capture or Balanced detail."))
        }
        var updated = entries
        updated[position].conversions.removeAll { $0.id == conversion.id }
        updated[position].conversions.append(conversion)
        try commit(updated)
    }
    public func setLimit(_ value: Int) throws {
        let newLimit = min(max(0, value), Self.maximumLimit)
        try commit(Array(entries.prefix(newLimit)))
        limit = newLimit
    }
    public func remove(_ id: UUID) throws { try commit(entries.filter { $0.id != id }) }
    public func clear() throws { try commit([]) }
    public var diskBytes: Int64 {
        let urls = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    private func commit(_ updated: [HistoryEntry]) throws {
        var persisted = updated
        var created: [URL] = []
        do {
            for entryIndex in persisted.indices {
                for resultIndex in persisted[entryIndex].conversions.indices {
                    var result = persisted[entryIndex].conversions[resultIndex]
                    guard !result.contentIsExternal else { continue }
                    let size = result.content.utf8.count
                    // Earlier versions allowed unrestricted manual text. Keep
                    // those existing inline results readable; only new saves
                    // are subject to the artifact size limit.
                    guard size <= Self.maximumContentBytes else { continue }
                    if size > Self.externalContentThreshold {
                        let name = "result-" + UUID().uuidString + ".txt"
                        let url = directory.appendingPathComponent(name)
                        let data = Data(result.content.utf8)
                        try data.write(to: url, options: .atomic)
                        created.append(url)
                        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                        result.externalize(to: name, data: data)
                        persisted[entryIndex].conversions[resultIndex] = result
                    }
                }
            }
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: indexURL, options: .atomic)
            // The new index is committed. Cleanup/permissions failures must not
            // make our in-memory state claim the old index is still current.
            entries = persisted
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
        } catch {
            let referenced = Set(entries.flatMap(\.conversions).compactMap(\.contentArtifact))
            for url in created where !referenced.contains(url.lastPathComponent) { try? files.removeItem(at: url) }
            throw error
        }
        let retained = Set(persisted.map { $0.id.uuidString + ".png" } + persisted.flatMap(\.conversions).compactMap(\.contentArtifact))
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let ownedImage = url.pathExtension == "png" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
            if (ownedImage || SavedConversion.validArtifactName(url.lastPathComponent)), !retained.contains(url.lastPathComponent) {
                try files.removeItem(at: url)
            }
        }
    }
}
