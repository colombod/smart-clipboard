import Foundation

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
    public var id: String { format.rawValue + ":" + (outputLanguage?.lowercased() ?? "source") }
    public let format: OutputFormat
    public var content: String
    public var instruction: String
    public var createdAt: Date
    public var provenance: ConversionProvenance?
    /// Resolved BCP 47 target; nil preserves source, "und" preserves legacy directions.
    public var outputLanguage: String?
    public init(format: OutputFormat, content: String, instruction: String, createdAt: Date = Date(), provenance: ConversionProvenance? = nil, outputLanguage: String? = nil) {
        self.format = format; self.content = content; self.instruction = instruction; self.createdAt = createdAt
        self.provenance = provenance
        self.outputLanguage = outputLanguage.flatMap(OutputLanguage.canonicalIdentifier)
    }

    private enum CodingKeys: String, CodingKey {
        case format, content, instruction, createdAt, provenance, outputLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(OutputFormat.self, forKey: .format)
        content = try container.decode(String.self, forKey: .content)
        instruction = try container.decode(String.self, forKey: .instruction)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        provenance = try container.decodeIfPresent(ConversionProvenance.self, forKey: .provenance)
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
        try container.encode(content, forKey: .content)
        try container.encode(instruction, forKey: .instruction)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(provenance, forKey: .provenance)
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
        let firstLine = conversions.last?.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? source
        return String(firstLine.prefix(80))
    }
}

/// Owned by the main actor in the app. Each original PNG is written once;
/// a small atomic index stores metadata and the latest result per format and output language.
public final class HistoryStore {
    public static let defaultLimit = 50
    public static let maximumLimit = 500
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
        let data = try JSONEncoder().encode(updated)
        try data.write(to: indexURL, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
        entries = updated
        let retained = Set(updated.map { $0.id.uuidString + ".png" })
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if url.pathExtension == "png", UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil, !retained.contains(url.lastPathComponent) {
                try files.removeItem(at: url)
            }
        }
    }
}
