import Foundation

public enum SVGMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case ai, trace
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ai: return L10n.text("Reconstruct with AI")
        case .trace: return L10n.text("Trace on device")
        }
    }
}

public enum TracePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo, logo
    case lineArt = "line-art"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .photo: return L10n.text("Photo")
        case .logo: return L10n.text("Logo")
        case .lineArt: return L10n.text("Line drawing")
        }
    }
}

public enum TraceDetail: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced, detailed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .balanced: return L10n.text("Balanced")
        case .detailed: return L10n.text("Detailed")
        }
    }
}

public struct TraceSettings: Codable, Equatable, Hashable, Sendable {
    public var preset: TracePreset
    public var detail: TraceDetail
    public init(preset: TracePreset = .photo, detail: TraceDetail = .balanced) {
        self.preset = preset
        self.detail = detail
    }
    public var variantID: String { preset.rawValue + ":" + detail.rawValue }
}

public enum ConversionMethod: String, Codable, CaseIterable, Sendable {
    case ai
    case appleVision = "apple-vision"
    case vtracer
}
