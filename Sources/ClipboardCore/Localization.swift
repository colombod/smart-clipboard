import Foundation

/// UI text follows the macOS language preference, independently of the language
/// of captured content. Protocol identifiers and user content are never keys.
public enum L10n {
    /// Use the interface language for native names (for example, language pickers),
    /// even when the Mac's region/date locale uses a different language.
    public static var locale: Locale {
        Locale(identifier: preferredLanguage(locale: nil, bundle: resourceBundle))
    }
    public struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
        let key: String
        let arguments: [String]

        public init(stringLiteral value: String) {
            key = value
            arguments = []
        }

        public init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []

            public init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity)
                arguments.reserveCapacity(interpolationCount)
            }

            public mutating func appendLiteral(_ literal: String) { key += literal }

            public mutating func appendInterpolation<Value>(_ value: Value) {
                arguments.append(String(describing: value))
                key += "%\(arguments.count)$@"
            }
        }
    }

    /// Interpolations become stable positional tokens, so translations can reorder
    /// arguments without interpreting argument content as localization or format code.
    public static func text(_ message: Message, locale: Locale? = nil) -> String {
        render(message, locale: locale, bundle: resourceBundle)
    }

    /// Use only for known UI keys chosen at runtime, never captured or user text.
    public static func key(_ source: String, locale: Locale? = nil) -> String {
        template(source, locale: locale, bundle: resourceBundle)
    }

    static let resourceBundle: Bundle? = {
        if Bundle.main.bundleURL.pathExtension == "app" {
            // Bundle.module embeds a development build path as a fallback. Installed
            // apps must be self-contained even if the checkout still exists.
            guard let resources = Bundle.main.resourceURL else { return nil }
            return Bundle(url: resources.appendingPathComponent("SmartClipboard_ClipboardCore.bundle"))
        }
        return Bundle.module
    }()

    static func render(_ message: Message, locale: Locale?, bundle: Bundle?) -> String {
        let translated = template(message.key, locale: locale, bundle: bundle)
        guard !message.arguments.isEmpty else { return translated }
        let expression = try! NSRegularExpression(pattern: "%([1-9][0-9]*)\\$@")
        let source = translated as NSString
        var result = translated
        // Match once and replace from the end. Tokens inside an inserted argument
        // stay literal, as do percent signs that are not positional placeholders.
        for match in expression.matches(in: translated, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let index = Int(source.substring(with: match.range(at: 1))),
                  message.arguments.indices.contains(index - 1),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: message.arguments[index - 1])
        }
        return result
    }

    static func template(_ source: String, locale: Locale?, bundle: Bundle?) -> String {
        guard let bundle else { return source }
        let preferred = preferredLanguage(locale: locale, bundle: bundle)
        for language in [preferred, "en"] {
            guard let path = bundle.path(forResource: language, ofType: "lproj"),
                  let localized = Bundle(path: path) else { continue }
            let missing = "\u{F0000}missing-localization"
            let value = localized.localizedString(forKey: source, value: missing, table: "Localizable")
            if value != missing { return value }
        }
        return source
    }

    private static func preferredLanguage(locale: Locale?, bundle: Bundle?) -> String {
        guard let bundle else { return "en" }
        let available = bundle.localizations.filter { $0 != "Base" }.sorted {
            if $0 == "en" { return $1 != "en" }
            if $1 == "en" { return false }
            return $0 < $1
        }
        let preferences = (locale.map { [$0.identifier] } ?? Locale.preferredLanguages)
            .map { $0.replacingOccurrences(of: "_", with: "-") }
        return Bundle.preferredLocalizations(from: available, forPreferences: preferences).first ?? "en"
    }
}
