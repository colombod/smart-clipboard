import Foundation

extension SavedConversion {
    /// Label the stored variant, not the current conversion preferences.
    public var variantTitle: String {
        if method == .vtracer {
            let settings = traceSettings ?? TraceSettings()
            return L10n.text("\(format.title) — \(SVGMethod.trace.title) — \(settings.preset.title), \(settings.detail.title)")
        }
        let methodTitle = method == .appleVision ? L10n.text("On-device text extraction") : L10n.text("AI")
        let language = OutputLanguage.fromResolvedIdentifier(outputLanguage).displayName()
        return L10n.text("\(format.title) — \(methodTitle) — \(language)")
    }
}
