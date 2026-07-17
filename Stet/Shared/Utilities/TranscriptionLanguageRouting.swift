import Foundation

enum TranscriptionLanguageRouting {
    static let parakeetSupportedLanguages: Set<String> = [
        "en", "es", "fr", "de", "it", "pt",
        "zh", "ja", "ko",
        "hi", "ar", "ru",
        "nl", "pl", "sv", "da", "no", "fi",
        "cs", "ro", "hu", "tr",
    ]

    static func resolveEngine(primary: String, secondary: String?) -> TranscriptionEngine {
        let asianLanguages: Set<String> = ["zh", "yue", "ja", "ko"]

        let isAsian: (String) -> Bool = { code in
            asianLanguages.contains(where: { code.hasPrefix($0) })
        }

        let isEuropean: (String) -> Bool = { code in
            let base = String(code.prefix(2))
            return parakeetSupportedLanguages.contains(base) || parakeetSupportedLanguages.contains(code)
        }

        // 1. Check if ALL selected languages are Asian (SenseVoice Zone: ZH, JA, KO)
        let primaryIsAsian = isAsian(primary)
        let secondaryIsAsian = secondary == nil || secondary == primary || isAsian(secondary!)

        if primaryIsAsian && secondaryIsAsian {
            return .sherpaOnnxSenseVoice
        }

        // 2. Check if ALL selected languages are European (Parakeet Zone)
        let primaryIsEU = isEuropean(primary)
        let secondaryIsEU = secondary == nil || secondary == primary || isEuropean(secondary!)

        if primaryIsEU && secondaryIsEU {
            return .fluidAudio
        }

        // 3. Everything else (Mixed cross-zone, e.g., Chinese+English)
        return .localWhisper(languageHint: nil)
    }
}
