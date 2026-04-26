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
        let isSupported: (String) -> Bool = { code in
            if parakeetSupportedLanguages.contains(code) { return true }
            let base = String(code.prefix(2))
            return parakeetSupportedLanguages.contains(base)
        }

        let primarySupported = isSupported(primary)
        let secondarySupported = secondary.map { isSupported($0) } ?? true

        if primarySupported && secondarySupported {
            return .fluidAudio
        } else {
            // Whisper with primary language hint if no secondary, otherwise nil hint for auto-detection
            return .localWhisper(languageHint: secondary == nil ? primary : nil)
        }
    }
}
