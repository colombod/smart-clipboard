import SwiftUI
import ClipboardCore

struct OutputLanguagePicker: View {
    let title: String
    @Binding var selection: OutputLanguage

    private var languages: [OutputLanguage] {
        var values = OutputLanguage.availableLanguages
        if case .language = selection, !values.contains(selection) { values.append(selection) }
        return values.sorted { $0.displayName().localizedStandardCompare($1.displayName()) == .orderedAscending }
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text(OutputLanguage.source.displayName()).tag(OutputLanguage.source)
            Text(systemLanguageTitle).tag(OutputLanguage.system)
            if selection == .directions {
                Text(OutputLanguage.directions.displayName()).tag(OutputLanguage.directions)
            }
            Divider()
            ForEach(languages) { language in
                Text(language.displayName()).tag(language)
            }
        }
        .accessibilityHint(L10n.text("Choose whether to keep the image’s language or translate the AI result."))
        if selection == .directions {
            Text(L10n.text("Your existing directions still control translation. Choose a language above to replace that behavior."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var systemLanguageTitle: String {
        let identifier = OutputLanguage.systemLanguageIdentifier
        let name = L10n.locale.localizedString(forIdentifier: identifier) ?? identifier
        return L10n.text("System language (\(name))")
    }
}

extension SavedConversion {
    var variantTitle: String {
        let language = OutputLanguage.fromResolvedIdentifier(outputLanguage).displayName()
        return L10n.text("\(format.title) — \(language)")
    }
}
