import Foundation

enum DictationLanguageMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case mixedChineseEnglish
    case primarilyChinese
    case primarilyEnglish

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .mixedChineseEnglish:
            return "Mixed Chinese + English"
        case .primarilyChinese:
            return "Primary Chinese"
        case .primarilyEnglish:
            return "Primary English"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .automatic:
            return "Auto-detect spoken language and keep the transcript in the same language or mix of languages."
        case .mixedChineseEnglish:
            return "Best for natural Chinese-English code-switching in the same sentence."
        case .primarilyChinese:
            return "Bias dictation toward Chinese while preserving English names, code, and technical terms."
        case .primarilyEnglish:
            return "Bias dictation toward English while preserving Chinese names, phrases, and code-switching."
        }
    }

    nonisolated var transcriptionLanguageCode: String? {
        switch self {
        case .automatic, .mixedChineseEnglish:
            return nil
        case .primarilyChinese:
            return "zh"
        case .primarilyEnglish:
            return "en"
        }
    }

    nonisolated var rewriteAdditionalContext: String? {
        switch self {
        case .automatic:
            return """
                Keep the transcript in the same spoken language or mix of languages as the speaker used.
                Never translate the transcript into a different language during cleanup.
                """
        case .mixedChineseEnglish:
            return """
                The speaker may naturally mix Chinese and English, even within the same sentence.
                Preserve that code-switching exactly where it is helpful and natural.
                Preserve English technical terms, brand names, product names, and code as spoken.
                Never rewrite the transcript into only Chinese or only English unless the speaker already did that.
                """
        case .primarilyChinese:
            return """
                The speaker mainly dictates in Chinese, but may naturally include English words, names, technical terms, and code.
                Prefer natural Chinese sentence boundaries and punctuation while preserving English insertions and code-switching.
                Never translate the full transcript into only English during cleanup.
                """
        case .primarilyEnglish:
            return """
                The speaker mainly dictates in English, but may naturally include Chinese words, names, phrases, and code-switching.
                Prefer natural English sentence boundaries and punctuation while preserving Chinese insertions where they were spoken.
                Never translate the full transcript into only Chinese during cleanup.
                """
        }
    }
}
