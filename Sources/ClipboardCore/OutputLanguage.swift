import Foundation

/// The language of extracted content is separate from the language of the app's interface.
public enum OutputLanguage: Hashable, Identifiable, Codable, Sendable, RawRepresentable {
    case source
    case system
    /// Keeps pre-language-picker directions working until the user chooses a language.
    case directions
    case language(String)

    public var id: String { rawValue }
    /// Read the global preference so a per-app interface-language override does not
    /// silently change a user's chosen "System language" translation target.
    public static var systemLanguageIdentifier: String {
        let globalLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return resolveSystemLanguage(globalPreferences: globalLanguages, processPreferences: Locale.preferredLanguages)
    }

    static func resolveSystemLanguage(globalPreferences: [String]?, processPreferences: [String]) -> String {
        globalPreferences?.compactMap(canonicalIdentifier).first ?? processPreferences.compactMap(canonicalIdentifier).first ?? "en"
    }

    public var rawValue: String {
        switch self {
        case .source: return "source"
        case .system: return "system"
        case .directions: return "directions"
        case .language(let identifier): return "language:" + (Self.canonicalIdentifier(identifier) ?? identifier)
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "source": self = .source
        case "system": self = .system
        case "directions": self = .directions
        default:
            guard rawValue.hasPrefix("language:"), let identifier = Self.canonicalIdentifier(String(rawValue.dropFirst(9))) else { return nil }
            self = .language(identifier)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let language = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid output language")
        }
        self = language
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Resolve once before an asynchronous operation; nil means preserve source languages.
    public func resolvedIdentifier(systemLanguage: String) -> String? {
        switch self {
        case .source: return nil
        case .system: return Self.canonicalIdentifier(systemLanguage) ?? "en"
        case .directions: return "und"
        case .language(let identifier): return Self.canonicalIdentifier(identifier)
        }
    }

    public static func fromResolvedIdentifier(_ identifier: String?) -> OutputLanguage {
        guard let identifier, let canonical = canonicalIdentifier(identifier) else { return .source }
        if canonical == "und" { return .directions }
        return .language(canonical)
    }

    public func displayName(in locale: Locale = L10n.locale) -> String {
        switch self {
        case .source: return L10n.text("Keep source language", locale: locale)
        case .system: return L10n.text("System language", locale: locale)
        case .directions: return L10n.text("Use saved directions", locale: locale)
        case .language(let identifier): return locale.localizedString(forIdentifier: identifier) ?? identifier
        }
    }

    /// Common translation targets. BCP 47 identifiers remain stable across interface languages.
    public static let availableLanguages: [OutputLanguage] = [
        "ar", "bg", "ca", "cs", "da", "de", "el", "en", "es", "et", "fa", "fi", "fr", "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "lt", "lv", "ms", "nb", "nl", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sl", "sr", "sv", "th", "tr", "uk", "ur", "vi", "zh-Hans", "zh-Hant"
    ].map { .language($0) }

    /// Adds one consistent policy to every provider without changing their wire contracts.
    /// App preferences take precedence over conflicting free-form directions.
    public static func instruction(userInstruction: String, resolvedIdentifier: String?) -> String {
        if resolvedIdentifier == "und" {
            return userInstruction
        }
        let policy: String
        if let identifier = resolvedIdentifier.flatMap(canonicalIdentifier) {
            let name = Locale(identifier: "en").localizedString(forIdentifier: identifier) ?? identifier
            policy = "Translate human-readable prose and labels into \(name) (BCP 47: \(identifier)). For descriptions, write in this language. Preserve code, commands, identifiers, URLs, numbers, units, proper names, and machine-readable keys and schema unless they are ordinary prose labels. Retain the requested output format and valid markup or structured syntax."
        } else {
            policy = "Keep the language or languages detected in the image; do not translate. Preserve multilingual text as shown. For descriptions, use the image's dominant readable language; if there is no readable text, use English."
        }
        return """
        \(userInstruction.isEmpty ? "No additional directions." : userInstruction)

        Output language policy (takes precedence over any conflicting translation directions above):
        \(policy)
        """
    }

    /// Accept language tags, never arbitrary free-form text, in the language policy.
    public static func canonicalIdentifier(_ identifier: String) -> String? {
        let components = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let first = components.first, (2...3).contains(first.count), first.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) && $0.isASCII }),
              components.dropFirst().allSatisfy({ (2...8).contains($0.count) && $0.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) }) else { return nil }
        return ([first.lowercased()] + components.dropFirst().map { component in
            if component.count == 2 { return component.uppercased() }
            if component.count == 4, component.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) { return component.prefix(1).uppercased() + component.dropFirst().lowercased() }
            return component.lowercased()
        }).joined(separator: "-")
    }
}
