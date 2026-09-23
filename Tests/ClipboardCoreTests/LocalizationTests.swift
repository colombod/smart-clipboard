import Foundation
import Testing
@testable import ClipboardCore

struct LocalizationTests {
    @Test func shippedTranslationsResolveWithoutChangingFormatIdentifiers() {
        for (language, settings) in [("en", "Settings"), ("it", "Impostazioni"), ("es", "Ajustes"),
                                     ("fr", "Réglages"), ("de", "Einstellungen")] {
            let locale = Locale(identifier: language)
            #expect(L10n.text("Settings", locale: locale) == settings)
            #expect(!OutputLanguage.source.displayName(in: locale).isEmpty)
        }
        #expect(OutputLanguage.source.displayName(in: Locale(identifier: "de")) != "Keep source language")
        #expect(OutputFormat.json.rawValue == "json")
        #expect(OutputFormat.auto.rawValue == "auto")
    }

    @Test func englishResourcesShipWithTheModule() throws {
        let bundle = try #require(L10n.resourceBundle)
        #expect(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en") != nil)
        #expect(L10n.text("Ready to paste", locale: Locale(identifier: "en")) == "Ready to paste")
    }

    @Test func regionalPreferenceUsesItsSupportedLanguage() throws {
        try withBundle { bundle in
            #expect(L10n.template("Ready", locale: Locale(identifier: "it-CH"), bundle: bundle) == "Pronto")
        }
    }

    @Test func unsupportedLanguageAndMissingTranslationFallBackToEnglish() throws {
        try withBundle { bundle in
            #expect(L10n.template("Ready", locale: Locale(identifier: "ja"), bundle: bundle) == "English ready")
            #expect(L10n.template("English-only entry", locale: Locale(identifier: "it"), bundle: bundle) == "English fallback")
            #expect(L10n.template("Unlisted UI text", locale: Locale(identifier: "it"), bundle: bundle) == "Unlisted UI text")
        }
    }

    @Test func translationReordersArgumentsWithoutTranslatingTheirContents() throws {
        try withBundle { bundle in
            let file = "Ready"
            let folder = "Utente 📁"
            #expect(L10n.render("Saved \(file) in \(folder).", locale: Locale(identifier: "it"), bundle: bundle)
                    == "In Utente 📁: Ready salvato.")
        }
    }

    @Test func insertedPlaceholdersAndPercentSignsAreLiteral() throws {
        try withBundle { bundle in
            let first = "%2$@ 100% %s %@"
            let second = "second"
            #expect(L10n.render("Saved \(first) in \(second).", locale: Locale(identifier: "it"), bundle: bundle)
                    == "In second: %2$@ 100% %s %@ salvato.")
            #expect(L10n.render("100% complete: \(first)", locale: Locale(identifier: "en"), bundle: bundle)
                    == "100% complete: %2$@ 100% %s %@")
        }
    }

    @Test func missingInstalledResourcesStillProduceReadableEnglish() {
        let name = "notes 📝"
        #expect(L10n.render("Saved \(name).", locale: Locale(identifier: "it"), bundle: nil) == "Saved notes 📝.")
        #expect(L10n.render("A literal %1$@ token", locale: nil, bundle: nil) == "A literal %1$@ token")
    }

    @Test func integerArgumentsAreInsertedWithoutPrintfTypeAssumptions() {
        #expect(L10n.render("Kept \(42) captures.", locale: Locale(identifier: "en"), bundle: nil) == "Kept 42 captures.")
    }

    private func withBundle(_ body: (Bundle) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("localization-tests-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "localization-tests.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL",
            "CFBundleDevelopmentRegion": "en",
            "CFBundleLocalizations": ["en", "it"]
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        let translations = [
            "en": ["Ready": "English ready", "English-only entry": "English fallback"],
            "it": ["Ready": "Pronto", "Saved %1$@ in %2$@.": "In %2$@: %1$@ salvato."]
        ]
        for (language, values) in translations {
            let folder = resources.appendingPathComponent("\(language).lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
                .write(to: folder.appendingPathComponent("Localizable.strings"))
        }
        try body(#require(Bundle(url: root)))
    }
}
