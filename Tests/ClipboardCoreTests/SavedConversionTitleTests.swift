import Foundation
import Testing
@testable import ClipboardCore

struct SavedConversionTitleTests {
    @Test func everyStoredTracePresetAndDetailHasADistinctLabel() {
        let results = TracePreset.allCases.flatMap { preset in
            TraceDetail.allCases.map { detail in
                SavedConversion(format: .svg, content: "", instruction: "", method: .vtracer,
                                traceSettings: TraceSettings(preset: preset, detail: detail))
            }
        }
        #expect(results.count == 6)
        #expect(Set(results.map(\.variantTitle)).count == results.count)
        for result in results {
            #expect(result.variantTitle.contains(SVGMethod.trace.title))
            #expect(result.variantTitle.contains(result.traceSettings!.preset.title))
            #expect(result.variantTitle.contains(result.traceSettings!.detail.title))
            #expect(!result.variantTitle.contains(OutputLanguage.source.displayName()))
        }
        let ai = SavedConversion(format: .svg, content: "", instruction: "")
        #expect(!results.map(\.variantTitle).contains(ai.variantTitle))
    }

    @Test func aiAndLocalTextLabelsKeepTheirMethodFormatAndSavedLanguage() {
        let aiSource = SavedConversion(format: .text, content: "", instruction: "")
        let localSource = SavedConversion(format: .text, content: "", instruction: "", method: .appleVision)
        let aiFrench = SavedConversion(format: .text, content: "", instruction: "", outputLanguage: "fr")
        let markdownFrench = SavedConversion(format: .markdown, content: "", instruction: "", outputLanguage: "fr")
        let directions = SavedConversion(format: .text, content: "", instruction: "Translate into French", outputLanguage: "und")
        let variants = [aiSource, localSource, aiFrench, markdownFrench, directions]
        #expect(Set(variants.map(\.variantTitle)).count == variants.count)
        #expect(aiSource.variantTitle.contains(L10n.text("AI")))
        #expect(localSource.variantTitle.contains(L10n.text("On-device text extraction")))
        #expect(aiFrench.variantTitle.contains(OutputLanguage.language("fr").displayName()))
        #expect(markdownFrench.variantTitle.contains(OutputFormat.markdown.title))
        #expect(directions.variantTitle.contains(OutputLanguage.directions.displayName()))
    }

    @Test func legacyTraceWithoutSettingsUsesTheSameDefaultLabel() {
        let defaults = SavedConversion(format: .svg, content: "", instruction: "", method: .vtracer)
        var legacy = defaults
        legacy.traceSettings = nil
        #expect(legacy.variantTitle == defaults.variantTitle)
        #expect(legacy.variantTitle.contains(TracePreset.photo.title))
        #expect(legacy.variantTitle.contains(TraceDetail.balanced.title))
    }
}
