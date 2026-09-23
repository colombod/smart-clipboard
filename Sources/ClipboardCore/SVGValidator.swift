import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Accepts bounded, static, self-contained vector documents. This is a safety
/// gate, not a guarantee that a model reconstructed the source accurately.
public enum SVGValidator {
    public static let maximumBytes = 16 * 1024 * 1024
    public static let maximumPaths = 100_000
    public static let maximumElements = 150_000
    public static let maximumDepth = 64

    public static func validate(_ content: String) throws {
        guard content.utf8.count <= maximumBytes else {
            throw ClipError.message(L10n.text("The SVG is too large. Try Balanced detail or a smaller capture."))
        }
        // Block DTDs before parsing, including internal entity expansion. XML
        // comments and the ordinary XML declaration remain compatible with tracers.
        let withoutComments = SVGGrammar.comments.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: "")
        guard !SVGGrammar.contains(SVGGrammar.declarations, withoutComments) else { throw invalid() }
        let parser = XMLParser(data: Data(content.utf8))
        let delegate = SVGDocumentValidator()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        guard parser.parse(), !delegate.failed, delegate.hasRoot, delegate.depth == 0,
              delegate.referencesAreBounded() else { throw invalid() }
    }

    private static func invalid() -> ClipError {
        .message(L10n.text("The SVG is invalid or contains unsupported content. Try another method or a smaller capture."))
    }
}

private enum SVGGrammar {
    static let namespace = "http://www.w3.org/2000/svg"
    static let xlink = "http://www.w3.org/1999/xlink"
    static let xml = "http://www.w3.org/XML/1998/namespace"
    static let numberPattern = #"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?"#
    static let number = try! NSRegularExpression(pattern: numberPattern)
    static let pathToken = try! NSRegularExpression(pattern: "[MmZzLlHhVvCcSsQqTtAa]|" + numberPattern)
    static let comments = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#)
    static let declarations = try! NSRegularExpression(pattern: #"<!\s*(?:DOCTYPE|ENTITY)\b"#, options: .caseInsensitive)
    static let forbidden = try! NSRegularExpression(pattern: #"[\x00-\x08\x0b\x0c\x0e-\x1f\\@]|(?:https?|file|ftp|javascript|data):|//|/\*|expression\s*\("#, options: .caseInsensitive)
    static let resource = try! NSRegularExpression(pattern: #"url\s*\(\s*['"]?(#[A-Za-z_][A-Za-z0-9_.:-]*)['"]?\s*\)"#, options: .caseInsensitive)
    static let anyURL = try! NSRegularExpression(pattern: #"url\s*\("#, options: .caseInsensitive)
    static let transform = try! NSRegularExpression(pattern: #"([A-Za-z]+)\s*\(([^()]*)\)"#)
    static let identifier = try! NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_.:-]*$"#)
    static let length = try! NSRegularExpression(pattern: "^(" + numberPattern + ")(?:px|pt|pc|mm|cm|in|em|ex|%)?$")
    static let cssRule = try! NSRegularExpression(pattern: #"([^{}]+)\{([^{}]*)\}"#)
    static let cssSelector = try! NSRegularExpression(pattern: #"^\s*(?:[.#]?[A-Za-z_][A-Za-z0-9_-]*|\*)(?:\s*,\s*(?:[.#]?[A-Za-z_][A-Za-z0-9_-]*|\*))*\s*$"#)
    static func contains(_ regex: NSRegularExpression, _ value: String) -> Bool {
        regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
    static func matches(_ regex: NSRegularExpression, _ value: String) -> [NSTextCheckingResult] {
        regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
    }
    static func separators(_ value: String) -> Bool { value.allSatisfy { $0.isWhitespace || $0 == "," } }
    static func finite(_ value: String) -> Double? {
        guard let number = Double(value), number.isFinite, abs(number) <= 1_000_000 else { return nil }
        return number
    }
    static func numbers(_ value: String) -> [Double]? {
        let matches = matches(number, value)
        var cursor = value.startIndex
        var values: [Double] = []
        for match in matches {
            guard let range = Range(match.range, in: value), separators(String(value[cursor..<range.lowerBound])),
                  let number = finite(String(value[range])) else { return nil }
            values.append(number); cursor = range.upperBound
        }
        return separators(String(value[cursor...])) ? values : nil
    }
    static func validPath(_ value: String) -> Bool {
        if value.isEmpty { return true }
        let matches = matches(pathToken, value)
        var cursor = value.startIndex
        var command: Character?
        var values: [Double] = []
        var first = true
        func segmentIsValid() -> Bool {
            guard let command else { return false }
            let name = String(command).uppercased()
            let arity = ["M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0][name]!
            if arity == 0 { return values.isEmpty }
            guard !values.isEmpty, values.count % arity == 0 else { return false }
            if name == "A" {
                for start in stride(from: 0, to: values.count, by: 7) {
                    if values[start] < 0 || values[start + 1] < 0 || ![0.0, 1.0].contains(values[start + 3]) || ![0.0, 1.0].contains(values[start + 4]) { return false }
                }
            }
            return true
        }
        for match in matches {
            guard let range = Range(match.range, in: value), separators(String(value[cursor..<range.lowerBound])) else { return false }
            let token = String(value[range]); cursor = range.upperBound
            if token.count == 1, let character = token.first, "MmZzLlHhVvCcSsQqTtAa".contains(character) {
                if first { guard character == "M" || character == "m" else { return false }; first = false }
                else if !segmentIsValid() { return false }
                command = character; values = []
            } else {
                guard command != nil, let number = finite(token) else { return false }
                values.append(number)
            }
        }
        return separators(String(value[cursor...])) && segmentIsValid()
    }
    static func validTransform(_ value: String) -> Bool {
        var cursor = value.startIndex
        for match in matches(transform, value) {
            guard let range = Range(match.range, in: value), separators(String(value[cursor..<range.lowerBound])),
                  let nameRange = Range(match.range(at: 1), in: value), let arguments = Range(match.range(at: 2), in: value),
                  let values = numbers(String(value[arguments])) else { return false }
            let name = String(value[nameRange])
            let allowed = ["matrix": [6], "translate": [1, 2], "scale": [1, 2], "rotate": [1, 3], "skewX": [1], "skewY": [1]]
            guard allowed[name]?.contains(values.count) == true else { return false }
            if name == "scale" && values.contains(where: { abs($0) > 1000 }) { return false }
            if name == "matrix" && values.prefix(4).contains(where: { abs($0) > 1000 }) { return false }
            if name.hasPrefix("skew") && values.contains(where: { abs($0) >= 89.9 }) { return false }
            cursor = range.upperBound
        }
        return separators(String(value[cursor...]))
    }
}

private final class SVGDocumentValidator: NSObject, XMLParserDelegate {
    var failed = false
    var hasRoot = false
    var depth = 0
    private var elements = 0
    private var paths = 0
    private var ids = Set<String>()
    private var references: [String] = []
    private var ancestorIDs: [String?] = []
    private var graph: [String: [String]] = [:]
    private var subtreeSizes: [String: Int] = [:]
    private var styleText: String?
    private var filterDepth: Int?
    private var filterPrimitives = 0
    private let tags = Set("svg g defs path rect circle ellipse line polyline polygon text tspan textPath title desc style linearGradient radialGradient stop clipPath mask pattern use marker filter feDropShadow feGaussianBlur feOffset feFlood feComposite feBlend feMerge feMergeNode feColorMatrix".split(separator: " ").map(String.init))
    private let attributes = Set("id class version viewBox width height x y x1 y1 x2 y2 cx cy r rx ry d points transform fill fill-opacity fill-rule stroke stroke-width stroke-opacity stroke-linecap stroke-linejoin stroke-miterlimit stroke-dasharray stroke-dashoffset opacity clip-path clip-rule mask maskUnits maskContentUnits preserveAspectRatio gradientUnits gradientTransform spreadMethod fx fy fr offset stop-color stop-opacity patternUnits patternContentUnits patternTransform marker-start marker-mid marker-end markerWidth markerHeight markerUnits refX refY orient font-family font-size font-weight font-style text-anchor dominant-baseline alignment-baseline letter-spacing word-spacing textLength lengthAdjust dx dy rotate vector-effect display visibility color shape-rendering text-rendering paint-order clipPathUnits href xlink:href xml:space style filter filterUnits primitiveUnits in in2 result operator k1 k2 k3 k4 stdDeviation flood-color flood-opacity type values".split(separator: " ").map(String.init))
    private let scalarLengths = Set("width height x y x1 y1 x2 y2 cx cy r rx ry fx fy fr stroke-width stroke-miterlimit stroke-dashoffset markerWidth markerHeight refX refY font-size letter-spacing word-spacing textLength dx dy".split(separator: " ").map(String.init))
    private let styleProperties = Set("fill fill-opacity fill-rule stroke stroke-width stroke-opacity stroke-linecap stroke-linejoin stroke-miterlimit stroke-dasharray stroke-dashoffset opacity clip-path clip-rule mask stop-color stop-opacity marker-start marker-mid marker-end font-family font-size font-weight font-style text-anchor dominant-baseline alignment-baseline letter-spacing word-spacing vector-effect display visibility color shape-rendering text-rendering paint-order filter flood-color flood-opacity".split(separator: " ").map(String.init))

    private func reject(_ parser: XMLParser) { failed = true; parser.abortParsing() }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        if ![SVGGrammar.namespace, SVGGrammar.xlink, SVGGrammar.xml].contains(namespaceURI) { reject(parser) }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes values: [String: String]) {
        guard !failed, styleText == nil, namespaceURI == SVGGrammar.namespace, tags.contains(name) else { return reject(parser) }
        depth += 1; elements += 1
        if name == "path" { paths += 1 }
        guard depth <= SVGValidator.maximumDepth, elements <= SVGValidator.maximumElements, paths <= SVGValidator.maximumPaths, values.count <= 100 else { return reject(parser) }
        if !hasRoot {
            guard name == "svg", let viewBox = values["viewBox"], let numbers = SVGGrammar.numbers(viewBox), numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return reject(parser) }
            hasRoot = true
        } else if depth == 1 { return reject(parser) }
        let id = values["id"]
        if let id {
            guard SVGGrammar.contains(SVGGrammar.identifier, id), ids.insert(id).inserted else { return reject(parser) }
            graph[id] = []; subtreeSizes[id] = 0
        }
        ancestorIDs.append(id)
        for id in ancestorIDs.compactMap({ $0 }) { subtreeSizes[id, default: 0] += 1 }
        if name == "filter" {
            guard filterDepth == nil else { return reject(parser) }
            filterDepth = depth; filterPrimitives = 0
        } else if filterDepth != nil {
            filterPrimitives += 1
            guard filterPrimitives <= 16 else { return reject(parser) }
        }
        for (attribute, value) in values {
            if attribute == "xmlns" || attribute.hasPrefix("xmlns:") {
                guard [SVGGrammar.namespace, SVGGrammar.xlink, SVGGrammar.xml].contains(value) else { return reject(parser) }
                continue
            }
            guard attributes.contains(attribute), value.utf8.count <= 262_144, validateAttribute(attribute, value) else { return reject(parser) }
        }
        if name == "style" { styleText = "" }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard !failed else { return }
        if name == "style", let text = styleText {
            styleText = nil
            guard validateStylesheet(text) else { return reject(parser) }
        }
        if filterDepth == depth { filterDepth = nil }
        _ = ancestorIDs.popLast(); depth -= 1
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if styleText != nil {
            styleText! += string
            if styleText!.utf8.count > 65_536 { reject(parser) }
        }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8) else { return reject(parser) }
        self.parser(parser, foundCharacters: text)
    }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) { reject(parser) }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { reject(parser) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { reject(parser) }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { reject(parser); return nil }
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { failed = true }

    private func reference(_ id: String) -> Bool {
        guard references.count < 4096, SVGGrammar.contains(SVGGrammar.identifier, id) else { return false }
        references.append(id)
        for ancestor in ancestorIDs.compactMap({ $0 }) { graph[ancestor, default: []].append(id) }
        return true
    }
    private func validateAttribute(_ name: String, _ value: String) -> Bool {
        guard !SVGGrammar.contains(SVGGrammar.forbidden, value) else { return false }
        if name == "href" || name == "xlink:href" { return value.hasPrefix("#") && reference(String(value.dropFirst())) }
        let resources = SVGGrammar.matches(SVGGrammar.resource, value)
        for match in resources {
            guard let range = Range(match.range(at: 1), in: value), reference(String(value[range].dropFirst())) else { return false }
        }
        let withoutURLs = SVGGrammar.resource.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "")
        if SVGGrammar.contains(SVGGrammar.anyURL, withoutURLs) { return false }
        if name == "style" { return validateDeclarations(value) }
        if name == "d" { return SVGGrammar.validPath(value) }
        if ["transform", "gradientTransform", "patternTransform"].contains(name) { return SVGGrammar.validTransform(value) }
        if name == "viewBox" {
            guard let values = SVGGrammar.numbers(value), values.count == 4 else { return false }
            return values[2] > 0 && values[3] > 0
        }
        if name == "points" { guard let values = SVGGrammar.numbers(value) else { return false }; return values.count % 2 == 0 }
        if ["rotate", "values"].contains(name) { return SVGGrammar.numbers(value)?.isEmpty == false }
        if name == "stroke-dasharray", value != "none" {
            guard let values = SVGGrammar.numbers(value), !values.isEmpty else { return false }
            return values.allSatisfy { $0 >= 0 }
        }
        if name == "offset" {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return SVGGrammar.finite(trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed) != nil
        }
        if name == "stdDeviation" {
            guard let values = SVGGrammar.numbers(value), (1...2).contains(values.count) else { return false }
            return values.allSatisfy { (0...100).contains($0) }
        }
        if scalarLengths.contains(name) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            // SVG permits a position list on text/tspan. Keep each finite.
            if ["x", "y", "dx", "dy"].contains(name), let values = SVGGrammar.numbers(trimmed), !values.isEmpty { return true }
            guard let match = SVGGrammar.length.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let range = Range(match.range(at: 1), in: trimmed), let number = SVGGrammar.finite(String(trimmed[range])) else { return false }
            if ["width", "height", "r", "rx", "ry", "fr", "stroke-width", "font-size", "markerWidth", "markerHeight"].contains(name), number < 0 { return false }
        }
        if ["opacity", "fill-opacity", "stroke-opacity", "stop-opacity", "flood-opacity", "k1", "k2", "k3", "k4"].contains(name) {
            return SVGGrammar.finite(value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        }
        return true
    }
    private func validateDeclarations(_ value: String) -> Bool {
        for rawDeclaration in value.split(separator: ";", omittingEmptySubsequences: true) {
            let declaration = rawDeclaration.trimmingCharacters(in: .whitespacesAndNewlines)
            if declaration.isEmpty { continue }
            guard let colon = declaration.firstIndex(of: ":") else { return false }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let content = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard styleProperties.contains(property), validateAttribute(property, content) else { return false }
        }
        return true
    }
    private func validateStylesheet(_ value: String) -> Bool {
        // Resource references belong on the element that uses them. Resolving
        // selectors here would require a CSS engine to detect resource cycles.
        guard !SVGGrammar.contains(SVGGrammar.forbidden, value),
              !SVGGrammar.contains(SVGGrammar.anyURL, value) else { return false }
        let rules = SVGGrammar.matches(SVGGrammar.cssRule, value)
        guard rules.count <= 256 else { return false }
        var cursor = value.startIndex
        for rule in rules {
            guard let range = Range(rule.range, in: value), value[cursor..<range.lowerBound].allSatisfy(\.isWhitespace),
                  let selector = Range(rule.range(at: 1), in: value), value[selector].count <= 256,
                  SVGGrammar.contains(SVGGrammar.cssSelector, String(value[selector])),
                  let body = Range(rule.range(at: 2), in: value), validateDeclarations(String(value[body])) else { return false }
            cursor = range.upperBound
        }
        return value[cursor...].allSatisfy(\.isWhitespace)
    }
    func referencesAreBounded() -> Bool {
        guard references.allSatisfy({ ids.contains($0) }) else { return false }
        var memo: [String: (cost: Int, height: Int)] = [:]
        func expansion(_ id: String, visited: Set<String>) -> (cost: Int, height: Int)? {
            guard !visited.contains(id), visited.count < 16 else { return nil }
            if let cached = memo[id] {
                return visited.count + cached.height <= 16 ? cached : nil
            }
            var cost = subtreeSizes[id, default: 1]
            var height = 1
            for child in graph[id, default: []] {
                guard let extra = expansion(child, visited: visited.union([id])), cost <= 500_000 - extra.cost else { return nil }
                cost += extra.cost
                height = max(height, extra.height + 1)
            }
            let result = (cost: cost, height: height)
            memo[id] = result; return result
        }
        var total = elements
        for id in references {
            guard let result = expansion(id, visited: []), total <= 500_000 - result.cost else { return false }
            total += result.cost
        }
        return true
    }
}
