import Foundation

/// Deterministic, rule-based punctuation normalizer.
///
/// After Apple Intelligence rewrite or local transcription, the output may contain
/// inconsistent punctuation widths — e.g. half-width commas inside Chinese text
/// or full-width periods inside English text.
///
/// `PunctuationNormalizer` fixes this in a single O(n) pass by:
/// 1. Checking the **immediate character context** around each punctuation mark.
/// 2. Using the Whisper-detected **language code** as a tiebreaker when context
///    is ambiguous (e.g. punctuation at string boundaries or surrounded by spaces).
enum PunctuationNormalizer {

    // MARK: - Public

    /// Normalize punctuation widths in `text` based on surrounding character
    /// context and the detected transcript language.
    ///
    /// - Parameters:
    ///   - text: The post-rewrite transcript text.
    ///   - languageCode: Whisper-detected language code (e.g. `"zh"`, `"ja"`, `"ko"`, `"en"`).
    ///     `nil` falls back to context-only normalization.
    /// - Returns: Text with punctuation widths corrected.
    static func normalize(_ text: String, languageCode: String?) -> String {
        guard !text.isEmpty else { return text }

        let chars = Array(text)
        var result = ""
        result.reserveCapacity(text.count)

        for i in 0..<chars.count {
            let char = chars[i]

            // --- Half-width → full-width? ---
            if let fullWidth = halfToFull(char, languageCode: languageCode) {
                if shouldBeFullWidth(chars, at: i, languageCode: languageCode) {
                    result.append(fullWidth)
                } else {
                    result.append(char)
                }
                continue
            }

            // --- Full-width → half-width? ---
            if let halfWidth = fullToHalf[char] {
                if shouldBeHalfWidth(chars, at: i, languageCode: languageCode) {
                    result.append(halfWidth)
                } else {
                    result.append(char)
                }
                continue
            }

            result.append(char)
        }

        return result
    }

    // MARK: - Mappings

    /// Chinese full-width mapping (default for CJK).
    private static let zhHalfToFull: [Character: Character] = [
        ",": "，", ".": "。", "?": "？", "!": "！",
        ":": "：", ";": "；",
    ]

    /// Japanese uses ideographic comma `、` instead of `，`.
    private static let jaHalfToFull: [Character: Character] = [
        ",": "、", ".": "。", "?": "？", "!": "！",
        ":": "：", ";": "；",
    ]

    /// Reverse mapping (full-width → half-width) — language-independent.
    private static let fullToHalf: [Character: Character] = [
        "，": ",", "。": ".", "？": "?", "！": "!",
        "：": ":", "；": ";", "、": ",",
    ]

    /// Pick the right half → full mapping for the detected language.
    private static func halfToFull(
        _ char: Character, languageCode: String?
    ) -> Character? {
        guard zhHalfToFull[char] != nil else { return nil }
        let lang = normalizedLang(languageCode)
        if lang == "ja" {
            return jaHalfToFull[char]
        }
        return zhHalfToFull[char]
    }

    // MARK: - Decision helpers

    /// Returns `true` when a half-width punctuation mark at `index` should be
    /// replaced with its full-width equivalent.
    private static func shouldBeFullWidth(
        _ chars: [Character], at index: Int, languageCode: String?
    ) -> Bool {
        let prevCJK = nearestNonWhitespaceCJK(chars, before: index)
        let nextCJK = nearestNonWhitespaceCJK(chars, after: index)

        // If either neighbour (skipping whitespace) is CJK → full-width.
        if prevCJK == true || nextCJK == true { return true }

        // Both neighbours are Latin (or digits) → keep half-width.
        if prevCJK == false && nextCJK == false { return false }

        // Ambiguous (boundary / only whitespace neighbours) → language tiebreaker.
        return isCJKLanguage(languageCode)
    }

    /// Returns `true` when a full-width punctuation mark at `index` should be
    /// replaced with its half-width equivalent.
    private static func shouldBeHalfWidth(
        _ chars: [Character], at index: Int, languageCode: String?
    ) -> Bool {
        let prevCJK = nearestNonWhitespaceCJK(chars, before: index)
        let nextCJK = nearestNonWhitespaceCJK(chars, after: index)

        // If either neighbour is CJK → keep full-width.
        if prevCJK == true || nextCJK == true { return false }

        // Both neighbours are Latin → convert to half-width.
        if prevCJK == false && nextCJK == false { return true }

        // Ambiguous → language tiebreaker.
        return !isCJKLanguage(languageCode)
    }

    // MARK: - Character classification

    /// Looks backward from `index` (exclusive) for the nearest non-whitespace
    /// character and returns whether it is CJK. Returns `nil` if no such
    /// character is found (start of string or only whitespace).
    private static func nearestNonWhitespaceCJK(
        _ chars: [Character], before index: Int
    ) -> Bool? {
        var j = index - 1
        while j >= 0 {
            let c = chars[j]
            if !c.isWhitespace { return isCJK(c) }
            j -= 1
        }
        return nil
    }

    /// Looks forward from `index` (exclusive) for the nearest non-whitespace
    /// character and returns whether it is CJK.
    private static func nearestNonWhitespaceCJK(
        _ chars: [Character], after index: Int
    ) -> Bool? {
        var j = index + 1
        while j < chars.count {
            let c = chars[j]
            if !c.isWhitespace { return isCJK(c) }
            j += 1
        }
        return nil
    }

    /// Returns `true` for CJK Unified Ideographs and Extension A.
    static func isCJK(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let v = scalar.value
        // CJK Unified Ideographs
        if v >= 0x4E00 && v <= 0x9FFF { return true }
        // CJK Extension A
        if v >= 0x3400 && v <= 0x4DBF { return true }
        // CJK Extension B
        if v >= 0x20000 && v <= 0x2A6DF { return true }
        // CJK Compatibility Ideographs
        if v >= 0xF900 && v <= 0xFAFF { return true }
        // Hiragana
        if v >= 0x3040 && v <= 0x309F { return true }
        // Katakana
        if v >= 0x30A0 && v <= 0x30FF { return true }
        // Hangul Syllables
        if v >= 0xAC00 && v <= 0xD7AF { return true }
        // Hangul Jamo
        if v >= 0x1100 && v <= 0x11FF { return true }
        // Bopomofo
        if v >= 0x3100 && v <= 0x312F { return true }
        return false
    }

    private static func isCJKLanguage(_ languageCode: String?) -> Bool {
        let lang = normalizedLang(languageCode)
        return lang == "zh" || lang == "ja" || lang == "ko"
    }

    /// Strips region subtags and normalises to lowercase.
    /// `"zh-Hans"` → `"zh"`, `"en-US"` → `"en"`, `nil` → `""`.
    private static func normalizedLang(_ code: String?) -> String {
        guard let code else { return "" }
        let lower = code.lowercased()
        if let dash = lower.firstIndex(of: "-") {
            return String(lower[lower.startIndex..<dash])
        }
        return lower
    }
}
