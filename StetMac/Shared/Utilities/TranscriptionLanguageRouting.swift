import Foundation
import StetCore

enum TranscriptionLanguageRouting {
    static let parakeetSupportedLanguages: Set<String> = [
        "en", "es", "fr", "de", "it", "pt",
        "zh", "ja", "ko",
        "hi", "ar", "ru",
        "nl", "pl", "sv", "da", "no", "fi",
        "cs", "ro", "hu", "tr",
    ]

    static func resolveEngine(primary: String, secondary: String?) -> TranscriptionEngine {
        let senseVoiceLanguages: Set<String> = ["zh", "yue", "ja", "ko"]

        let usesSenseVoiceLanguage: (String) -> Bool = { code in
            senseVoiceLanguages.contains(where: { code.hasPrefix($0) })
        }

        let usesParakeetLanguage: (String) -> Bool = { code in
            let base = String(code.prefix(2))
            return parakeetSupportedLanguages.contains(base) || parakeetSupportedLanguages.contains(code)
        }

        var languages = [primary]
        if let secondary, secondary != primary {
            languages.append(secondary)
        }

        if languages.allSatisfy(usesSenseVoiceLanguage) {
            return .sherpaOnnxSenseVoice
        }

        if languages.allSatisfy({
            !usesSenseVoiceLanguage($0) && usesParakeetLanguage($0)
        }) {
            return .fluidAudio
        }

        return .localWhisper(languageHint: nil)
    }
}
